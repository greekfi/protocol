// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IPermit2} from "./interaces/IPermit2.sol";

import "@openzeppelin/contracts/proxy/Clones.sol";

using SafeERC20 for IERC20;
// The Long Option contract is the owner of the Short Option contract
// The Long Option contract is the only one that can mint new options
// The Long Option contract is the only one that can exercise options
// The redemption is only possible if you own both the Long and Short Option contracts but 
// performed by the Long Option contract

// In options traditionally a Consideration is cash and a Collateral is an asset
// Here, we do not distinguish between the Cash and Asset concept and allow consideration
// to be any asset and collateral to be any asset as well. This can allow wETH to be used
// as collateral and wBTC to be used as consideration. Similarly, staked ETH can be used
// or even staked stable coins can be used as well for either consideration or collateral.

contract OptionBase is ERC20, Ownable, ReentrancyGuard {

    IPermit2 public constant PERMIT2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);
    string public _name;
    string public _symbol;
    uint256 public  expirationDate;
    uint256 public  strike;
    uint256 public constant STRIKE_DECIMALS = 10**18;
    // The strike price includes the ratio of the consideration to the collateral
    // and the decimal difference between the consideration and collateral along
    // with the strike decimals of 18. 
    bool public isPut;
    IERC20 public collateral;
    IERC20 public consideration;
    error ContractNotExpired();
    error ContractExpired();
    error InsufficientBalance();
    error InvalidValue();

    modifier expired() {
        if (block.timestamp < expirationDate) revert ContractNotExpired();
        _;
    }

    modifier notExpired() {
        if (block.timestamp >= expirationDate) revert ContractExpired();
        
        _;
    }

    modifier validAmount(uint256 amount) {
        if (amount == 0) revert InvalidValue();
        _;
    }

    modifier sufficientBalance(address contractHolder, uint256 amount) {
        if (balanceOf(contractHolder) < amount) revert InsufficientBalance();
        _;
    }


    constructor(
        string memory name_, 
        string memory symbol_, 
        address collateral_, 
        address consideration_,
        uint256 expirationDate_, 
        uint256 strike_,
        bool isPut_
        ) 
        ERC20(name_, symbol_) 
        Ownable(msg.sender) 
        ReentrancyGuard() {


        if (collateral_ == address(0)) revert InvalidValue();
        if (consideration_ == address(0)) revert InvalidValue();
        if (strike_ == 0) revert InvalidValue();
        if (expirationDate_ < block.timestamp) revert InvalidValue();

        expirationDate = expirationDate_;
        strike = strike_;
        isPut = isPut_;
        collateral = IERC20(collateral_);
        consideration = IERC20(consideration_);
        }

        function toConsideration(uint256 amount) public view returns (uint256 ) {
            // The strike price actually contains the ratio of Consideration
            // over Collateral including the decimals associated. The ratio is 
            // multiplied by 10**18 as is the standard convention. That's why 
            // we eventually divide by the STRIKE_DECIMALS. MulDiv?
            return (amount * strike)/ STRIKE_DECIMALS;
        }

        function init(
            string memory name_, 
            string memory symbol_,
            address collateral_,
            address consideration_,
            uint256 expirationDate_, 
            uint256 strike_,
            bool isPut_
        ) public onlyOwner() {
            _name = name_;
            _symbol = symbol_;
            collateral = IERC20(collateral_);
            consideration = IERC20(consideration_);
            expirationDate = expirationDate_;
            strike = strike_;
            isPut = isPut_;
        }

}

contract ShortOption is OptionBase {

    address public longOption;

    event Redemption(
        address longOption,
        address holder,
        uint256 amount
    );

    modifier sufficientCollateral(address contractHolder, uint256 amount) {
        if (collateral.balanceOf(contractHolder) < amount) {
            revert InsufficientBalance();
        }
        _;
    }

    constructor(
        string memory name, 
        string memory symbol, 
        address collateral, 
        address consideration,
        uint256 expirationDate, 
        uint256 strike,
        bool isPut
        ) OptionBase(name, symbol, collateral, consideration, expirationDate, strike, isPut) {
        }
    function setLongOption(address longOption_) public onlyOwner() {
        longOption = longOption_;
    }

    function mint(address to, uint256 amount) public onlyOwner sufficientCollateral(to, amount) validAmount(amount) notExpired {
        __mint(to, amount);
    }

    function __mint(address to, uint256 amount) private nonReentrant sufficientCollateral(to, amount) validAmount(amount) {
        collateral.safeTransferFrom(to, address(this), amount);
        _mint(to, amount);
    }

    function mint2(address to, uint256 amount, IPermit2.PermitSingle calldata permitDetails, bytes calldata signature) 
    public onlyOwner sufficientCollateral(to, amount) validAmount(amount) notExpired {
        PERMIT2.permit(to, permitDetails, signature);
        _mint2(to, amount);
    }

    function _mint2(address to, uint256 amount) private nonReentrant sufficientCollateral(to, amount) validAmount(amount) {
        PERMIT2.transferFrom(to, address(this), uint160(amount), address(collateral));
        _mint(to, amount);
    }

    function _redeem(address to, uint256 amount) private nonReentrant sufficientBalance(to, amount) validAmount(amount){

        uint256 collateralBalance = collateral.balanceOf(address(this));
        uint256 considerationBalance = consideration.balanceOf(address(this));
        
        // First try to fulfill with collateral
        uint256 collateralToSend = amount <= collateralBalance ? amount : collateralBalance;
        
        // Burn the redeemed tokens
        _burn(to, amount);
        // If we couldn't fully fulfill with collateral, try to fulfill remainder with consideration
        if (collateralToSend < amount) {
            uint256 remainingAmount = amount - collateralToSend;
            uint256 considerationNeeded = toConsideration(remainingAmount);
            
            // Verify we have enough consideration tokens; this should never happen
            if (considerationBalance < considerationNeeded) {
                revert InsufficientBalance();
            }
            
            // Transfer consideration tokens for the remaining amount
            consideration.safeTransfer(to, considerationNeeded);
        }
        
        // Transfer whatever collateral we can
        if (collateralToSend > 0) {
            collateral.safeTransfer(to, collateralToSend);
        }
        emit Redemption(address(longOption), to, amount);

    }

    function _redeemConsideration(address to, uint256 amount) private nonReentrant sufficientBalance(to, amount) validAmount(amount){
        // Verify we have enough consideration tokens
        uint256 considerationAmount = toConsideration(amount);
        if (consideration.balanceOf(address(this)) < considerationAmount) revert InsufficientBalance();
        _burn(to, amount);
        // Transfer consideration tokens for the remaining amount
        consideration.safeTransfer(to, considerationAmount);
        emit Redemption(address(longOption), to, amount);

    }

    function redeem(uint256 amount) public expired sufficientBalance(msg.sender, amount) {
        _redeem(msg.sender, amount);
    }

    function redeemConsideration(uint256 amount) public sufficientBalance(msg.sender, amount) expired {
        _redeemConsideration(msg.sender, amount);
    }

    function _redeemPair(address to, uint256 amount) public notExpired onlyOwner() sufficientBalance(to, amount) {
        _redeem(to, amount);
    }

    function _exercise(address contractHolder, uint256 amount) private nonReentrant notExpired onlyOwner() {
        uint256 considerationAmount = toConsideration(amount);
        if (consideration.balanceOf(contractHolder) < considerationAmount) revert InsufficientBalance();
        consideration.safeTransferFrom(contractHolder, address(this), considerationAmount);
        collateral.safeTransfer(contractHolder, amount);
    }

    function exercise(address contractHolder, uint256 amount) public notExpired onlyOwner() {
        _exercise(contractHolder, amount);
    }

    function _exercise2(address contractHolder, uint256 amount) public notExpired onlyOwner() nonReentrant {
        uint256 considerationAmount = toConsideration(amount);
        if (consideration.balanceOf(contractHolder) < considerationAmount) revert InsufficientBalance();
        
        PERMIT2.transferFrom(contractHolder, address(this), uint160(considerationAmount), address(consideration));
        collateral.safeTransfer(contractHolder, amount);
    }

    function exercise2(address contractHolder, uint256 amount, IPermit2.PermitSingle calldata permitDetails, bytes calldata signature) public notExpired onlyOwner() {
        PERMIT2.permit(contractHolder, permitDetails, signature);
        _exercise2(contractHolder, amount);
    }

    function sweep(address holder) public expired sufficientBalance(holder, balanceOf(holder)) {
        _redeem(holder, balanceOf(holder));
    }

}

contract LongOption is OptionBase {
    ShortOption public shortOption;


    event Exercise(
        address longOption,
        address holder,
        uint256 amount
    );

    constructor (
        string memory name,
        string memory symbol,
        address collateral,
        address consideration,
        uint256 expirationDate,
        uint256 strike,
        bool isPut,
        address shortOptionAddress_
    ) OptionBase(
        name, 
        symbol, 
        collateral, 
        consideration, 
        expirationDate, 
        strike, 
        isPut
    ) {
        shortOption = ShortOption(shortOptionAddress_);


    } 

    function mint(uint256 amount) public nonReentrant validAmount(amount) notExpired {
        _mint(msg.sender, amount);
        shortOption.mint(msg.sender, amount);
    }

    function mint2(uint256 amount, IPermit2.PermitSingle calldata permitDetails, bytes calldata signature) public nonReentrant validAmount(amount) notExpired {
        _mint(msg.sender, amount);
        shortOption.mint2(msg.sender, amount, permitDetails, signature);
    }

    function exercise(uint256 amount) public notExpired nonReentrant validAmount(amount) {
        _burn(msg.sender, amount);
        shortOption.exercise(msg.sender, amount);
        emit Exercise(address(this), msg.sender, amount);
    }

    function exercise2(uint256 amount, IPermit2.PermitSingle calldata permitDetails, bytes calldata signature) public notExpired nonReentrant validAmount(amount) {
        _burn(msg.sender, amount);
        shortOption.exercise2(msg.sender, amount, permitDetails, signature);
        emit Exercise(address(this), msg.sender, amount);
    }

    function redeem(uint256 amount) 
        public 
        notExpired 
        nonReentrant
        sufficientBalance(msg.sender, amount) 
        validAmount(amount){
        if (shortOption.balanceOf(msg.sender) < amount) revert InsufficientBalance();

        address contractHolder = msg.sender;
        _burn(contractHolder, amount);
        shortOption._redeemPair(contractHolder, amount);
    }
}

contract OptionFactory is Ownable {

    address public shortContract;
    address public longContract;

    event OptionCreated(
        address longOption,
        address shortOption,
        address collateral, 
        address consideration,
        uint256 expirationDate, 
        uint256 strike,
        bool isPut
    );

    address[] public createdOptions;
    mapping (uint256 => address[])  public shortLong;

    mapping(address => mapping(uint256 => mapping(uint256 => address[]))) public allOptions;

    constructor(address short_, address long_) Ownable(msg.sender) {
        shortContract = short_;
        longContract = long_;
    }

    function createOption(
        string memory longOptionName, 
        string memory shortOptionName,
        string memory longSymbol,
        string memory shortSymbol,
        address collateral, 
        address consideration, 
        uint256 expirationDate, 
        uint256 strike,
        bool isPut
        ) public {

        address short = Clones.clone(shortContract);
        address long = Clones.clone(longContract);

        ShortOption shortOption = ShortOption(short);
        LongOption longOption = LongOption(long);

        shortOption.init(
            shortOptionName, 
            shortSymbol, 
            collateral, 
            consideration, 
            expirationDate, 
            strike,
            isPut
        );

        longOption.init(
            longOptionName, 
            longSymbol, 
            collateral, 
            consideration, 
            expirationDate, 
            strike, 
            isPut
        );
        
        createdOptions.push(long);
        allOptions[collateral][expirationDate][strike].push(long);
        shortOption.setLongOption(long);
        shortOption.transferOwnership(long);
        longOption.transferOwnership(owner());

        emit OptionCreated(
            long,
            short, 
            collateral, 
            consideration,
            expirationDate, 
            strike,
            isPut
        );
    }

    function getCreatedOptions() public view returns (address[] memory) {
        return createdOptions;
    }
    // function getOption(address collateral, uint256 expiration, uint256 strike) public view returns (address[] memory) {
    //     return allOptions[collateral][expiration][strike];
    // }

}