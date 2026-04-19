// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuardTransient } from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

import { Option } from "./Option.sol";
import { Collateral } from "./Collateral.sol";
import { CreateParams } from "./interfaces/IFactory.sol";
import { IPriceOracle } from "./oracles/IPriceOracle.sol";
import { IUniswapV3Pool, UniV3Oracle } from "./oracles/UniV3Oracle.sol";

using SafeERC20 for ERC20;

/**
 * @title Factory
 * @notice Immutable factory deploying Option + Collateral pairs as EIP-1167 clones.
 *         Also serves as the single approval point for collateral/consideration transfers
 *         and operator approvals across all options it has created.
 *
 *         Oracle mode is per-option: caller passes `oracleSource` (Uniswap v3 pool for now;
 *         Chainlink branch added in a later plan) and the factory deploys a fresh oracle
 *         wrapper bound to the option's expiration during `createOption`.
 */
contract Factory is Ownable, ReentrancyGuardTransient {
    address public immutable COLL_CLONE;
    address public immutable OPTION_CLONE;

    mapping(address => bool) private colls; // registered Collateral contracts
    mapping(address => bool) public options;

    mapping(address => bool) public blocklist;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => mapping(address => bool)) private _approvedOperators;
    mapping(address => bool) public autoMintRedeem;

    error BlocklistedToken();
    error InvalidAddress();
    error InvalidTokens();
    error InsufficientAllowance();
    error EuropeanRequiresOracle();
    error UnsupportedOracleSource();

    event OptionCreated(
        address indexed collateral,
        address indexed consideration,
        uint40 expirationDate,
        uint96 strike,
        bool isPut,
        bool isEuro,
        address oracle,
        address indexed option,
        address coll
    );
    event TokenBlocked(address token, bool blocked);
    event OperatorApproval(address indexed owner, address indexed operator, bool approved);
    event AutoMintRedeemUpdated(address indexed account, bool enabled);
    event Approval(address indexed token, address indexed owner, uint256 amount);

    constructor(address collClone_, address optionClone_) Ownable(msg.sender) {
        if (collClone_ == address(0) || optionClone_ == address(0)) revert InvalidAddress();
        COLL_CLONE = collClone_;
        OPTION_CLONE = optionClone_;
    }

    // ============ OPTION CREATION ============

    function createOption(CreateParams memory p) public nonReentrant returns (address) {
        if (blocklist[p.collateral] || blocklist[p.consideration]) revert BlocklistedToken();
        if (p.collateral == p.consideration) revert InvalidTokens();
        if (p.isEuro && p.oracleSource == address(0)) revert EuropeanRequiresOracle();

        address coll_ = Clones.clone(COLL_CLONE);
        address option_ = Clones.clone(OPTION_CLONE);

        address oracle_ = address(0);
        if (p.oracleSource != address(0)) {
            oracle_ = _deployOracle(p);
        }

        Collateral(coll_)
            .init(
                p.collateral,
                p.consideration,
                p.expirationDate,
                p.strike,
                p.isPut,
                p.isEuro,
                oracle_,
                option_,
                address(this)
            );
        Option(option_).init(coll_, msg.sender);

        colls[coll_] = true;
        options[option_] = true;

        emit OptionCreated(
            p.collateral, p.consideration, p.expirationDate, p.strike, p.isPut, p.isEuro, oracle_, option_, coll_
        );
        return option_;
    }

    function createOptions(CreateParams[] memory params) external returns (address[] memory result) {
        result = new address[](params.length);
        for (uint256 i = 0; i < params.length; i++) {
            result[i] = createOption(params[i]);
        }
    }

    /// @notice Backward-compat overload: American non-settled (no oracle).
    function createOption(
        address collateral_,
        address consideration_,
        uint40 expirationDate_,
        uint96 strike_,
        bool isPut_
    ) external returns (address) {
        return createOption(
            CreateParams({
                collateral: collateral_,
                consideration: consideration_,
                expirationDate: expirationDate_,
                strike: strike_,
                isPut: isPut_,
                isEuro: false,
                oracleSource: address(0),
                twapWindow: 0
            })
        );
    }

    /// @dev Detects oracle source type and returns the oracle address.
    ///      Supported sources (in detection order):
    ///        1. Pre-deployed IPriceOracle whose expiration matches — used directly.
    ///        2. Uniswap v3 pool — UniV3Oracle wrapper is deployed inline.
    ///      Chainlink aggregator: reserved for a future plan, currently reverts.
    function _deployOracle(CreateParams memory p) internal returns (address) {
        try IPriceOracle(p.oracleSource).expiration() returns (uint256 exp) {
            if (exp == p.expirationDate) return p.oracleSource;
        } catch { }
        try IUniswapV3Pool(p.oracleSource).token0() returns (address) {
            return
                address(new UniV3Oracle(p.oracleSource, p.collateral, p.consideration, p.expirationDate, p.twapWindow));
        } catch { }
        revert UnsupportedOracleSource();
    }

    // ============ CENTRALIZED TRANSFER ============

    function transferFrom(address from, address to, uint160 amount, address token)
        external
        nonReentrant
        returns (bool)
    {
        if (!colls[msg.sender]) revert InvalidAddress();
        uint256 currentAllowance = _allowances[token][from];
        if (currentAllowance < amount) revert InsufficientAllowance();
        if (currentAllowance != type(uint256).max) {
            _allowances[token][from] = currentAllowance - amount;
        }
        ERC20(token).safeTransferFrom(from, to, amount);
        return true;
    }

    function allowance(address token, address owner_) public view returns (uint256) {
        return _allowances[token][owner_];
    }

    function approve(address token, uint256 amount) public {
        if (token == address(0)) revert InvalidAddress();
        _allowances[token][msg.sender] = amount;
        emit Approval(token, msg.sender, amount);
    }

    // ============ OPERATOR APPROVAL ============

    function approveOperator(address operator, bool approved) external {
        if (operator == address(0)) revert InvalidAddress();
        if (operator == msg.sender) revert InvalidAddress();
        _approvedOperators[msg.sender][operator] = approved;
        emit OperatorApproval(msg.sender, operator, approved);
    }

    function approvedOperator(address owner_, address operator) external view returns (bool) {
        return _approvedOperators[owner_][operator];
    }

    function enableAutoMintRedeem(bool enabled) external {
        autoMintRedeem[msg.sender] = enabled;
        emit AutoMintRedeemUpdated(msg.sender, enabled);
    }

    // ============ BLOCKLIST ============

    function blockToken(address token) external onlyOwner nonReentrant {
        if (token == address(0)) revert InvalidAddress();
        blocklist[token] = true;
        emit TokenBlocked(token, true);
    }

    function unblockToken(address token) external onlyOwner nonReentrant {
        if (token == address(0)) revert InvalidAddress();
        blocklist[token] = false;
        emit TokenBlocked(token, false);
    }

    function isBlocked(address token) external view returns (bool) {
        return blocklist[token];
    }
}
