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
 * @title  Factory — deployer, allowance hub, operator registry
 * @author Greek.fi
 * @notice The only on-chain contract users need to interact with to *create* options. Once deployed,
 *         every Option + Collateral pair runs off pre-compiled template clones, so creation is
 *         cheap and the factory is never an upgradeable rug vector (the templates are immutable).
 *
 *         The factory also plays three lasting roles post-creation:
 *
 *         1. **Single allowance point.** Users `approve(collateralToken, amount)` on the factory once,
 *            and any Option / Collateral pair created by this factory can pull from that allowance
 *            via {transferFrom}. No need to approve every new option individually.
 *
 *         2. **Operator registry.** {approveOperator} gives an address blanket authority to move
 *            any Option produced by this factory on your behalf — the ERC-1155-style "setApprovalForAll"
 *            pattern. Used by trading venues and aggregators.
 *
 *         3. **Auto-mint / auto-redeem opt-in.** {enableAutoMintRedeem} flips a per-account flag that
 *            Option consults on transfer to auto-mint deficits and auto-redeem matched Option+Collateral
 *            on the receiving side.
 *
 *         ### Token blocklist
 *
 *         The factory owner can {blockToken} / {unblockToken} to prevent options from being created
 *         against known-problematic tokens (fee-on-transfer, rebasing, exploited). It never affects
 *         already-created options — only new creations.
 *
 *         ### Oracle sources
 *
 *         `createOption(params)` auto-detects the oracle source in `params.oracleSource`:
 *
 *         - Pre-deployed `IPriceOracle` whose `expiration()` matches → reused in place.
 *         - Uniswap v3 pool (detected via `token0()`) → a fresh {UniV3Oracle} is deployed inline,
 *           bound to `(collateral, consideration, expiration, twapWindow)`.
 *         - Anything else → reverts with `UnsupportedOracleSource`. A Chainlink branch is planned.
 *
 * @dev    Example (create + approve + mint):
 *         ```solidity
 *         // Create a 30-day WETH/USDC 3000 call, European, settled by a v3 TWAP on a WETH/USDC pool.
 *         address opt = factory.createOption(
 *             CreateParams({
 *                 collateral:     WETH,
 *                 consideration:  USDC,
 *                 expirationDate: uint40(block.timestamp + 30 days),
 *                 strike:         uint96(3000e18),
 *                 isPut:          false,
 *                 isEuro:         true,
 *                 oracleSource:   UNIV3_WETH_USDC_POOL,
 *                 twapWindow:     1800                   // 30-min TWAP
 *             })
 *         );
 *
 *         // Single approval feeds every option this factory creates.
 *         IERC20(WETH).approve(address(factory), type(uint256).max);
 *         factory.approve(WETH, type(uint256).max);
 *
 *         Option(opt).mint(1e18);
 *         ```
 */
contract Factory is Ownable, ReentrancyGuardTransient {
    /// @notice Template Collateral contract; per-option instances are EIP-1167 clones of this.
    address public immutable COLL_CLONE;
    /// @notice Template Option contract; per-option instances are EIP-1167 clones of this.
    address public immutable OPTION_CLONE;

    /// @dev Registered Collateral clones — `transferFrom` is only callable by these.
    mapping(address => bool) private colls;

    /// @notice `true` if the address is a Option clone this factory created.
    mapping(address => bool) public options;

    /// @notice Tokens rejected for new option creation. Does not affect already-created options.
    mapping(address => bool) public blocklist;

    /// @dev Per-token allowance table: `_allowances[token][owner] -> amount`.
    mapping(address => mapping(address => uint256)) private _allowances;

    /// @dev Operator approval table: `_approvedOperators[owner][operator] -> bool`.
    mapping(address => mapping(address => bool)) private _approvedOperators;

    /// @notice Per-account opt-in for auto-mint on transfer and auto-redeem on receive in {Option}.
    mapping(address => bool) public autoMintRedeem;

    /// @notice Thrown when {createOption} is called against a blocklisted collateral or consideration token.
    error BlocklistedToken();
    /// @notice Thrown when a zero address is supplied where a real contract is required.
    error InvalidAddress();
    /// @notice Thrown when `collateral == consideration` (no real option pair).
    error InvalidTokens();
    /// @notice Thrown when {transferFrom} is called with `allowance < amount`.
    error InsufficientAllowance();
    /// @notice Thrown when `isEuro == true` but no oracle source was provided.
    error EuropeanRequiresOracle();
    /// @notice Thrown when {createOption} cannot classify `oracleSource` (neither an `IPriceOracle` nor a v3 pool).
    error UnsupportedOracleSource();

    /// @notice Emitted for every newly-created option.
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
    /// @notice Emitted on {blockToken} / {unblockToken}.
    event TokenBlocked(address token, bool blocked);
    /// @notice Emitted on {approveOperator}.
    event OperatorApproval(address indexed owner, address indexed operator, bool approved);
    /// @notice Emitted on {enableAutoMintRedeem}.
    event AutoMintRedeemUpdated(address indexed account, bool enabled);
    /// @notice Emitted on {approve} (factory-level allowance set by token owner).
    event Approval(address indexed token, address indexed owner, uint256 amount);

    /// @notice Bind the factory to its immutable templates.
    /// @param collClone_   Deployed Collateral template.
    /// @param optionClone_ Deployed Option template.
    constructor(address collClone_, address optionClone_) Ownable(msg.sender) {
        if (collClone_ == address(0) || optionClone_ == address(0)) revert InvalidAddress();
        COLL_CLONE = collClone_;
        OPTION_CLONE = optionClone_;
    }

    // ============ OPTION CREATION ============

    /// @notice Deploy a new Option + Collateral pair.
    /// @dev    Clones the templates, classifies / deploys an oracle if needed, and initialises both
    ///         sides. Emits {OptionCreated}. The caller becomes the {Option}'s admin owner.
    /// @param p See {CreateParams}:
    ///          - `collateral`, `consideration`: ERC20 addresses; must differ and not be blocklisted.
    ///          - `expirationDate`: unix timestamp; must be in the future.
    ///          - `strike`: 18-decimal fixed point (consideration per collateral, inverted for puts).
    ///          - `isPut`, `isEuro`: option flavour flags. `isEuro` requires an oracle.
    ///          - `oracleSource`: pre-deployed `IPriceOracle`, a Uniswap v3 pool, or `address(0)`.
    ///          - `twapWindow`: seconds of TWAP when `oracleSource` is a v3 pool (ignored otherwise).
    /// @return The new {Option} address.
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

    /// @notice Batch form of {createOption}. Same ordering in → same ordering out.
    /// @param params Array of {CreateParams}.
    /// @return result Array of newly-created Option addresses, aligned with `params`.
    function createOptions(CreateParams[] memory params) external returns (address[] memory result) {
        result = new address[](params.length);
        for (uint256 i = 0; i < params.length; i++) {
            result[i] = createOption(params[i]);
        }
    }

    /// @notice Backward-compatibility overload for the American non-settled case (no oracle, American).
    /// @param collateral_    Collateral token.
    /// @param consideration_ Consideration token.
    /// @param expirationDate_ Expiration timestamp.
    /// @param strike_        18-decimal strike.
    /// @param isPut_         Put/call flag.
    /// @return New {Option} address.
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

    /// @dev Classify `p.oracleSource` and return a concrete oracle address.
    ///      Detection order:
    ///        1. Object already quacks like an `IPriceOracle` and its `expiration()` matches — reuse.
    ///        2. Object quacks like a Uniswap v3 pool (`token0()` succeeds) — wrap in a fresh {UniV3Oracle}.
    ///        3. Otherwise — revert.
    ///      A Chainlink aggregator branch is reserved for a later change.
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

    /// @notice Pull `amount` of `token` from `from` to `to`. Only callable by Collateral clones
    ///         that this factory has created.
    /// @dev    Decrements `_allowances[token][from]` (unless it is `type(uint256).max`).
    ///         This is the mechanism by which a single user approval on the factory flows to every
    ///         option pair it creates, rather than requiring approvals on each Collateral clone.
    /// @param from   Token owner.
    /// @param to     Recipient (typically the calling Collateral contract).
    /// @param amount Token amount to transfer (≤ `uint160.max`, matching Permit2 semantics).
    /// @param token  Token to move.
    /// @return success Always `true` on success; reverts otherwise.
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

    /// @notice Factory-level allowance lookup: how much of `token` can the factory pull from `owner_`?
    /// @param token  Token.
    /// @param owner_ Token owner.
    /// @return Current allowance.
    function allowance(address token, address owner_) public view returns (uint256) {
        return _allowances[token][owner_];
    }

    /// @notice Set the caller's factory-level allowance for `token` to `amount`.
    /// @dev    This is the shared approval consumed by every Option + Collateral pair created by
    ///         this factory. Does not replace the ERC20-level `token.approve(factory, ...)` the
    ///         user must also grant so the factory can call `safeTransferFrom` on the token.
    /// @param token  ERC20 to be approved.
    /// @param amount Allowance to grant (use `type(uint256).max` for infinite).
    function approve(address token, uint256 amount) public {
        if (token == address(0)) revert InvalidAddress();
        _allowances[token][msg.sender] = amount;
        emit Approval(token, msg.sender, amount);
    }

    // ============ OPERATOR APPROVAL ============

    /// @notice Grant or revoke `operator` blanket authority to move any of the caller's Option tokens
    ///         across every option this factory has created (ERC-1155-style `setApprovalForAll`).
    /// @dev    Used by trading venues to avoid per-option approvals. Operators also skip the
    ///         per-transfer `_spendAllowance` step on {Option.transferFrom}.
    /// @param operator Address being approved/revoked (must differ from `msg.sender`).
    /// @param approved `true` to grant, `false` to revoke.
    function approveOperator(address operator, bool approved) external {
        if (operator == address(0)) revert InvalidAddress();
        if (operator == msg.sender) revert InvalidAddress();
        _approvedOperators[msg.sender][operator] = approved;
        emit OperatorApproval(msg.sender, operator, approved);
    }

    /// @notice Is `operator` an approved operator for `owner_`?
    function approvedOperator(address owner_, address operator) external view returns (bool) {
        return _approvedOperators[owner_][operator];
    }

    /// @notice Opt in to {Option}'s auto-mint-on-send and auto-redeem-on-receive transfer behaviour.
    /// @dev    Scoped to `msg.sender`. See {Option} for the full semantics — in short, enabling lets
    ///         the caller treat Option and its backing collateral as interchangeable.
    ///
    /// Example:
    /// ```solidity
    /// factory.enableAutoMintRedeem(true);
    /// // Now: `option.transfer(bob, 1e18)` will auto-mint if the sender is short Option but long collateral.
    /// ```
    function enableAutoMintRedeem(bool enabled) external {
        autoMintRedeem[msg.sender] = enabled;
        emit AutoMintRedeemUpdated(msg.sender, enabled);
    }

    // ============ BLOCKLIST ============

    /// @notice Block `token` from being used as collateral or consideration for new options.
    /// @dev    Owner-only. Does not retroactively affect existing options — use {Option.lock} for that.
    function blockToken(address token) external onlyOwner nonReentrant {
        if (token == address(0)) revert InvalidAddress();
        blocklist[token] = true;
        emit TokenBlocked(token, true);
    }

    /// @notice Reverse of {blockToken}.
    function unblockToken(address token) external onlyOwner nonReentrant {
        if (token == address(0)) revert InvalidAddress();
        blocklist[token] = false;
        emit TokenBlocked(token, false);
    }

    /// @notice Is `token` on the blocklist?
    function isBlocked(address token) external view returns (bool) {
        return blocklist[token];
    }
}
