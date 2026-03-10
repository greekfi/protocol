// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { Option } from "./Option.sol";
import { Redemption } from "./Redemption.sol";
import { OptionParameter } from "./interfaces/IOptionFactory.sol";
import { ReentrancyGuardTransient } from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuardTransient.sol";

using SafeERC20 for ERC20;

/**
 * @title OptionFactory
 * @notice Immutable factory that deploys Option + Redemption pairs as EIP-1167 minimal proxy clones
 * @dev Central hub for option pair lifecycle:
 *
 *      Deployment: template contracts are deployed once; each createOption() call produces
 *      a pair of gas-efficient clones (Option + Redemption) initialized with the given parameters.
 *
 *      Token transfers: all collateral/consideration movements go through transferFrom()
 *      which is restricted to registered Redemption contracts. This provides a single
 *      approval point — users approve the factory once, then interact with any option pair.
 *
 *      Fee flow: fees are collected as collateral in Redemption contracts on mint.
 *      Claiming is permissionless: anyone can trigger Redemption → Factory → Owner.
 *
 *      Operator approvals: ERC-1155-style setApprovalForAll() allows approved operators
 *      to transfer ANY option token created by this factory on behalf of an owner.
 *
 *      Auto-mint/redeem: opt-in per-account feature (enableAutoMintRedeem) that enables
 *      auto-minting on transfer when sender balance < amount, and auto-redeeming matched
 *      Option+Redemption pairs when receiving Options.
 *
 *      Token blocklist: prevents creation of options using fee-on-transfer or rebasing tokens.
 *
 *      Ownership: deployer is owner, controls fee adjustment and blocklist.
 *      Not upgradeable — the factory is immutable to eliminate the rug vector from
 *      owner-controlled implementation swaps (users approve tokens to the factory).
 */
contract OptionFactory is Ownable, ReentrancyGuardTransient {
    // ============ STATE VARIABLES ============

    /// @notice Address of the Redemption template contract used for EIP-1167 cloning
    address public immutable redemptionClone;

    /// @notice Address of the Option template contract used for EIP-1167 cloning
    address public immutable optionClone;

    /// @notice Protocol fee in 1e18 basis (e.g., 0.0001e18 = 0.01%). Applied on mint.
    uint64 public fee;

    /// @notice Maximum allowed fee: 1% (0.01e18)
    uint256 public constant MAX_FEE = 0.01e18; // 1%

    // ============ ERRORS ============

    error BlocklistedToken();
    error InvalidAddress();
    error InvalidTokens();
    error InsufficientAllowance();

    // ============ EVENTS ============

    event OptionCreated(
        address indexed collateral,
        address indexed consideration,
        uint40 expirationDate,
        uint96 strike,
        bool isPut,
        address indexed option,
        address redemption
    );

    event TokenBlocked(address token, bool blocked);
    event FeeUpdated(uint64 oldFee, uint64 newFee);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    event AutoMintRedeemUpdated(address indexed account, bool enabled);
    event Approval(address indexed token, address indexed owner, uint256 amount);

    // ============ STORAGE MAPPINGS ============

    /// @notice Tracks registered Redemption contracts — only these can call transferFrom()
    mapping(address => bool) private redemptions;

    /// @notice Tracks registered Option contracts created by this factory
    mapping(address => bool) public options;

    /// @notice Blocklist for fee-on-transfer and rebasing tokens
    mapping(address => bool) public blocklist;

    /// @notice Factory-level token allowances: token => owner => amount
    /// @dev Users approve tokens to the factory once, then all option pairs can pull via transferFrom()
    mapping(address => mapping(address => uint256)) private _allowances;

    /// @notice Universal operator approvals: owner => operator => approved
    /// @dev When approved, operator can transfer ANY option token created by this factory on behalf of owner
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    /// @notice Opt-in flag for auto-mint and auto-redeem during Option transfers
    /// @dev When enabled: transferring Options auto-mints deficit from collateral (sender),
    ///      and receiving Options auto-redeems matched Redemption pairs (recipient)
    mapping(address => bool) public autoMintRedeem;

    // ============ CONSTRUCTOR ============

    /**
     * @notice Deploys the factory with template contracts and fee
     * @param redemption_ Redemption template to clone
     * @param option_ Option template to clone
     * @param fee_ Protocol fee in 1e18 basis (must be <= MAX_FEE)
     */
    constructor(address redemption_, address option_, uint64 fee_) Ownable(msg.sender) {
        require(fee_ <= MAX_FEE, "fee too high");
        if (redemption_ == address(0) || option_ == address(0)) revert InvalidAddress();

        redemptionClone = redemption_;
        optionClone = option_;
        fee = fee_;
    }

    // ============ OPTION CREATION FUNCTIONS ============

    /**
     * @notice Creates a new Option + Redemption pair via EIP-1167 minimal proxy cloning
     * @dev Clones both templates, initializes them, and registers the addresses.
     *      Reverts if either token is blocklisted or if collateral == consideration.
     *      The Option is owned by msg.sender; the Redemption is owned by the Option contract.
     * @param collateral Collateral token (what backs the option, deposited on mint)
     * @param consideration Consideration token (paid on exercise)
     * @param expirationDate Unix timestamp when the option expires
     * @param strike Strike price in 18-decimal fixed-point
     * @param isPut True for put option, false for call
     * @return Address of the created Option contract
     */
    function createOption(address collateral, address consideration, uint40 expirationDate, uint96 strike, bool isPut)
        public
        nonReentrant
        returns (address)
    {
        // Check blocklist for fee-on-transfer and rebasing tokens
        if (blocklist[collateral] || blocklist[consideration]) revert BlocklistedToken();
        if (collateral == consideration) revert InvalidTokens();

        address redemption_ = Clones.clone(redemptionClone);
        address option_ = Clones.clone(optionClone);

        Redemption redemption = Redemption(redemption_);
        Option option = Option(option_);

        redemption.init(collateral, consideration, expirationDate, strike, isPut, option_, address(this), fee);
        option.init(redemption_, msg.sender, fee);
        redemptions[redemption_] = true;
        options[option_] = true;

        emit OptionCreated(collateral, consideration, expirationDate, strike, isPut, option_, redemption_);
        return option_;
    }

    /**
     * @notice Batch creates multiple option pairs in a single transaction
     * @param optionParams Array of OptionParameter structs defining each option
     * @return options_ Array of created Option contract addresses
     */
    function createOptions(OptionParameter[] memory optionParams) public returns (address[] memory options_) {
        options_ = new address[](optionParams.length);
        for (uint256 i = 0; i < optionParams.length; i++) {
            OptionParameter memory param = optionParams[i];
            options_[i] =
                createOption(param.collateral_, param.consideration_, param.expiration, param.strike, param.isPut);
        }
        return options_;
    }

    // ============ TOKEN TRANSFER FUNCTION ============

    /**
     * @notice Transfers tokens from `from` to `to` using factory-level allowances
     * @dev Only callable by registered Redemption contracts (used during mint and exercise).
     *      Provides a single approval point: users approve tokens to the factory once,
     *      then any option pair can pull via this function.
     *      Allowance is decremented unless set to type(uint256).max (infinite approval).
     * @param from Address to pull tokens from
     * @param to Address to send tokens to
     * @param amount Amount of tokens (uint160 for Permit2 compatibility)
     * @param token ERC20 token to transfer
     * @return success Always true (reverts on failure)
     */
    function transferFrom(address from, address to, uint160 amount, address token)
        external
        nonReentrant
        returns (bool success)
    {
        // Only redemption contracts can call this (used in mint() and exercise())
        if (!redemptions[msg.sender]) revert InvalidAddress();
        uint256 currentAllowance = allowance(token, from);
        if (currentAllowance < amount) revert InsufficientAllowance();
        if (currentAllowance != type(uint256).max) {
            _allowances[token][from] = currentAllowance - amount;
        }
        ERC20(token).safeTransferFrom(from, to, amount);
        return true;
    }

    /**
     * @notice Returns the factory-level allowance for a token and owner
     * @param token ERC20 token address
     * @param owner_ Token owner address
     * @return Remaining allowance
     */
    function allowance(address token, address owner_) public view returns (uint256) {
        return _allowances[token][owner_];
    }

    /**
     * @notice Sets factory-level allowance for a token
     * @dev Users call this to allow the factory to pull their tokens during mint/exercise.
     *      Use type(uint256).max for infinite approval.
     * @param token ERC20 token to approve
     * @param amount Allowance amount
     */
    function approve(address token, uint256 amount) public {
        if (token == address(0)) revert InvalidAddress();
        _allowances[token][msg.sender] = amount;
        emit Approval(token, msg.sender, amount);
    }

    // ============ UNIVERSAL OPERATOR APPROVAL FUNCTIONS ============

    /**
     * @notice Grants or revokes universal operator approval for all option tokens
     * @dev ERC-1155-style approval. Once set, the operator can transferFrom() on any
     *      Option contract created by this factory without needing individual ERC20 approvals.
     *      Cannot approve self or zero address.
     * @param operator Address to grant or revoke approval for
     * @param approved True to approve, false to revoke
     */
    function setApprovalForAll(address operator, bool approved) external {
        if (operator == address(0)) revert InvalidAddress();
        if (operator == msg.sender) revert InvalidAddress(); // Can't approve self
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    /**
     * @notice Checks if an operator has universal approval for an owner's option tokens
     * @param owner_ Token owner
     * @param operator Address to check
     * @return True if operator is approved for all option transfers
     */
    function isApprovedForAll(address owner_, address operator) external view returns (bool) {
        return _operatorApprovals[owner_][operator];
    }

    /**
     * @notice Opts the caller into or out of auto-mint and auto-redeem on Option transfers
     * @dev When enabled:
     *      - Sending more Options than you own auto-mints the deficit (pulls collateral)
     *      - Receiving Options while holding Redemption tokens auto-redeems matched pairs
     *      Default is disabled (standard ERC20 behavior).
     * @param enabled True to opt in, false to opt out
     */
    function enableAutoMintRedeem(bool enabled) external {
        autoMintRedeem[msg.sender] = enabled;
        emit AutoMintRedeemUpdated(msg.sender, enabled);
    }

    // ============ BLOCKLIST MANAGEMENT FUNCTIONS ============

    /**
     * @notice Adds a token to the blocklist, preventing future option creation with it
     * @dev Use for fee-on-transfer, rebasing, or otherwise incompatible tokens.
     *      Does not affect already-deployed option pairs. Only callable by owner.
     * @param token Token address to blocklist
     */
    function blockToken(address token) external onlyOwner nonReentrant {
        if (token == address(0)) revert InvalidAddress();
        blocklist[token] = true;
        emit TokenBlocked(token, true);
    }

    /**
     * @notice Removes a token from the blocklist
     * @dev Re-enables option creation with this token. Only callable by owner.
     * @param token Token address to unblock
     */
    function unblockToken(address token) external onlyOwner nonReentrant {
        if (token == address(0)) revert InvalidAddress();
        blocklist[token] = false;
        emit TokenBlocked(token, false);
    }

    /// @notice Returns true if the token is blocklisted
    function isBlocked(address token) external view returns (bool) {
        return blocklist[token];
    }

    // ============ FEE MANAGEMENT FUNCTIONS ============

    /**
     * @notice Combined fee claim: pulls fees from option contracts, then forwards all factory balances to owner
     * @dev Permissionless — anyone can trigger. Funds always go to the factory owner.
     *      Two-hop flow: Redemption → Factory (via optionsClaimFees), then Factory → Owner (via claimFees).
     * @param options_ Option contract addresses to claim fees from
     * @param tokens Token addresses to forward from factory to owner
     */
    function claimFees(address[] memory options_, address[] memory tokens) public {
        optionsClaimFees(options_);
        claimFees(tokens);
    }

    /**
     * @notice Forwards all factory-held token balances to the owner
     * @dev Permissionless — anyone can trigger. The factory accumulates fees from Redemption
     *      contracts; this function sends them to the owner.
     * @param tokens Token addresses to forward
     */
    function claimFees(address[] memory tokens) public nonReentrant {
        for (uint256 i = 0; i < tokens.length; i++) {
            ERC20 token_ = ERC20(tokens[i]);
            uint256 amount = token_.balanceOf(address(this));
            token_.safeTransfer(owner(), amount);
        }
    }

    /**
     * @notice Triggers fee transfer from Redemption → Factory for multiple option contracts
     * @dev Permissionless — anyone can trigger. Each Option.claimFees() moves accumulated
     *      collateral fees from the Redemption contract to this factory. Only works for
     *      options created by this factory (validates against the options registry).
     * @param options_ Option contract addresses to claim fees from
     */
    function optionsClaimFees(address[] memory options_) public nonReentrant {
        for (uint256 i = 0; i < options_.length; i++) {
            if (!options[options_[i]]) revert InvalidAddress();
            Option(options_[i]).claimFees();
        }
    }

    /**
     * @notice Adjusts the protocol fee for future option pair deployments
     * @dev Only affects options created after this call. Existing pairs keep their fee
     *      (use Option.adjustFee() to change individual pairs). Only callable by owner.
     * @param fee_ New fee in 1e18 basis (must be <= MAX_FEE = 1%)
     */
    function adjustFee(uint64 fee_) public onlyOwner nonReentrant {
        require(fee_ <= MAX_FEE, "fee exceeds maximum");
        uint64 oldFee = fee;
        fee = fee_;
        emit FeeUpdated(oldFee, fee_);
    }
}
