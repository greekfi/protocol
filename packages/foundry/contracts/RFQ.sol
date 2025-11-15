// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import {AccessControl} from "../lib/openzeppelin-contracts/contracts/access/AccessControl.sol"; // for mulDiv

contract RFQ {
    using SafeERC20 for IERC20;

    // Price is expressed as tokenOut per 1 tokenIn in 1e18 fixed-point (q = out/in).
    struct Order {
        address maker;
        address tokenA; // ETH
        address tokenB; // USDC
        uint256 priceA; // (tokenB per tokenA) * 1e18 (3000USD/ETH)
		uint256 priceB; // (tokenA per tokenB) * 1e18 (1ETH/4000USD)
		uint256 maxOutA; // total maker is willing to sell on this order
		uint256 maxOutB; // total maker is willing to sell on this order
        uint256 deadline; // unix seconds
        uint256 nonce; // unique per maker
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
                o.tokenA,
                o.tokenB,
                o.priceA,
				o.maxOutA,
				o.maxOutB,
                o.deadline,
                o.nonce,
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

    /// @notice Validates an order and returns remaining fillable amount
    /// @param o The order to validate
    /// @param sig The signature from the maker
    /// @param filler The address attempting to fill (use address(0) to skip filler check)
    /// @return remaining The amount of tokenIn still available to fill
    function validateOrder(Order calldata o, bytes calldata sig, address filler) public view returns (bool) {
        require(block.timestamp <= o.deadline, "expired");
        require(!canceled[o.maker][o.nonce], "canceled");
        if (o.allowedFiller != address(0) && filler != address(0)) {
            require(filler == o.allowedFiller, "not rfq filler");
        }

        // Signature validation
        bytes32 digest = _hashOrder(o);
        address signer = ECDSA.recover(digest, sig);
        require(signer == o.maker, "bad sig");
		return true;
    }

    // Filler chooses inAmt (size). Contract derives outAmt by signed price.
    function fill(Order calldata o, bytes calldata sig, address token, uint256 inAmt) external {
        // Validate order and get remaining fillable amount
        uint256 remaining = validateOrder(o, sig, msg.sender);
		uint256 outAmt;
        // Guardrails on fill size
        require(inAmt > 0, "size=0");
		require(token==o.tokenB || token==o.tokenA, "token chosen is not part of order");
		if (token==o.tokenB){ // sending in B to receive A
			outAmt = Math.mulDiv(inAmt, o.priceA, 1e18, Math.Rounding.Ceil);
			require(o.maxOutA==0 || outAmt<o.maxOutA, "Out token quantity exceeds Maker Max");
			// Swap
			IERC20(o.tokenB).safeTransferFrom(msg.sender, o.maker, inAmt);
			IERC20(o.tokenA).safeTransferFrom(o.maker, msg.sender, outAmt);
		} else {
			outAmt = Math.mulDiv(inAmt, o.priceB, 1e18, Math.Rounding.Ceil);
			require(o.maxOutB==0 || outAmt<o.maxOutB, "Out token quantity exceeds Maker Max");
			// Swap
			IERC20(o.tokenA).safeTransferFrom(msg.sender, o.maker, inAmt);
			IERC20(o.tokenB).safeTransferFrom(o.maker, msg.sender, outAmt);
		}

        bytes32 digest = _hashOrder(o);
        emit Filled(digest, o.maker, msg.sender, inAmt, outAmt);
    }
}
