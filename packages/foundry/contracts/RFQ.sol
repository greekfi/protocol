// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import { ECDSA } from "openzeppelin-contracts/utils/cryptography/ECDSA.sol";
import { MessageHashUtils } from "openzeppelin-contracts/utils/cryptography/MessageHashUtils.sol";
import { Math } from "openzeppelin-contracts/utils/math/Math.sol"; // for mulDiv

contract PriceIntent {
    using SafeERC20 for IERC20;

    // Price is expressed as tokenOut per 1 tokenIn in 1e18 fixed-point (q = out/in).
    struct Order {
        address maker;
        address tokenIn;
        address tokenOut;
        uint256 price1e18; // tokenOut per tokenIn * 1e18
        uint256 maxIn; // total maker is willing to sell/buy on this order
        uint256 minPerFillIn; // optional guardrail
        uint256 maxPerFillIn; // optional guardrail (0 => no limit)
        uint256 deadline; // unix seconds
        uint256 nonce; // unique per maker
        bool makerSellsIn; // true: maker sells tokenIn for tokenOut at price
        address allowedFiller; // optional RFQ (0 => public)
        uint256 feeBps; // optional fee taken from takerOut or makerIn depending on policy
    }

    bytes32 public constant ORDER_TYPEHASH = keccak256(
        "Order(address maker,address tokenIn,address tokenOut,uint256 price1e18,uint256 maxIn,uint256 minPerFillIn,uint256 maxPerFillIn,uint256 deadline,uint256 nonce,bool makerSellsIn,address allowedFiller,uint256 feeBps)"
    );
    bytes32 public immutable DOMAIN_SEPARATOR;

    // maker => nonce => filledIn
    mapping(address => mapping(uint256 => uint256)) public filledIn;
    mapping(address => mapping(uint256 => bool)) public canceled;

    event Filled(bytes32 orderHash, address maker, address filler, uint256 inAmt, uint256 outAmt);
    event Canceled(address maker, uint256 nonce);

    constructor() {
        uint256 chainId;
        assembly { chainId := chainid() }
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("PriceIntent")),
                keccak256(bytes("1")),
                chainId,
                address(this)
            )
        );
    }

    function _hashOrder(Order calldata o) internal view returns (bytes32) {
        bytes32 s = keccak256(
            abi.encode(
                ORDER_TYPEHASH,
                o.maker,
                o.tokenIn,
                o.tokenOut,
                o.price1e18,
                o.maxIn,
                o.minPerFillIn,
                o.maxPerFillIn,
                o.deadline,
                o.nonce,
                o.makerSellsIn,
                o.allowedFiller,
                o.feeBps
            )
        );
        return MessageHashUtils.toTypedDataHash(DOMAIN_SEPARATOR, s);
    }

    function cancel(uint256 nonce) external {
        canceled[msg.sender][nonce] = true;
        emit Canceled(msg.sender, nonce);
    }

    // Filler chooses inAmt (size). Contract derives outAmt by signed price.
    function fill(Order calldata o, bytes calldata sig, uint256 inAmt) external {
        require(block.timestamp <= o.deadline, "expired");
        require(!canceled[o.maker][o.nonce], "canceled");
        if (o.allowedFiller != address(0)) require(msg.sender == o.allowedFiller, "not rfq filler");

        // Signature
        bytes32 digest = _hashOrder(o);
        address signer = ECDSA.recover(digest, sig);
        require(signer == o.maker, "bad sig");

        // Guardrails
        require(inAmt > 0, "size=0");
        if (o.minPerFillIn > 0) require(inAmt >= o.minPerFillIn, "lt min fill");
        if (o.maxPerFillIn > 0) require(inAmt <= o.maxPerFillIn, "gt max fill");

        uint256 already = filledIn[o.maker][o.nonce];
        require(already < o.maxIn, "fully filled");
        uint256 remaining = o.maxIn - already;
        if (inAmt > remaining) inAmt = remaining; // clamp

        // Compute outAmt = inAmt * price / 1e18, round in maker's favor
        uint256 outAmt =
            Math.mulDiv(inAmt, o.price1e18, 1e18, o.makerSellsIn ? Math.Rounding.Floor : Math.Rounding.Ceil);

        // Optional: apply fee (example: fee taken from taker receives)
        if (o.feeBps > 0) {
            uint256 fee = (outAmt * o.feeBps) / 10_000;
            outAmt -= fee;
            // send fee to some recipient if desired
        }

        // Transfers: two cases depending on maker side
        if (o.makerSellsIn) {
            // Maker gives tokenIn, receives tokenOut at fixed price
            IERC20(o.tokenIn).safeTransferFrom(o.maker, msg.sender, inAmt);
            IERC20(o.tokenOut).safeTransferFrom(msg.sender, o.maker, outAmt);
        } else {
            // Maker buys tokenIn with tokenOut (price is tokenOut per tokenIn)
            IERC20(o.tokenIn).safeTransferFrom(msg.sender, o.maker, inAmt);
            IERC20(o.tokenOut).safeTransferFrom(o.maker, msg.sender, outAmt);
        }

        filledIn[o.maker][o.nonce] = already + inAmt;
        emit Filled(digest, o.maker, msg.sender, inAmt, outAmt);
    }
}
