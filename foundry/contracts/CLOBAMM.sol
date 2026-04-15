// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {TickMath} from "./libraries/TickMath.sol";

interface IToken2 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IOption2 {
    function collateral() external view returns (address);
    function factory() external view returns (address);
}

interface IFactorySetup {
    function enableAutoMintRedeem(bool enabled) external;
    function approve(address token, uint256 amount) external;
}

/// @title CLOBAMM — named-maker order book with shared liquidity
/// @notice Makers deposit once, quote across all pairs and ticks without fragmenting.
///         One balance backs everything. Fills check balance at execution time.
///         FIFO within each level. No shares, no accumulator, no settle.
contract CLOBAMM {

    modifier lock() {
        assembly ("memory-safe") {
            if tload(0) { revert(0, 0) }
            tstore(0, 1)
        }
        _;
        assembly ("memory-safe") {
            tstore(0, 0)
        }
    }

    // ============================================================
    //                        DATA MODEL
    // ============================================================

    /// @notice Global balance per maker per token — shared across all pairs
    mapping(address => mapping(address => uint256)) public balances;

    /// @notice How much a maker is willing to sell at a specific level
    mapping(address => mapping(bytes32 => uint256)) public commitments;

    /// @notice Makers at each level + index for O(1) removal
    mapping(bytes32 => address[]) public levelMakers;
    mapping(bytes32 => mapping(address => uint256)) internal _makerIdx;

    /// @notice Maker's active levels + index for O(1) removal
    mapping(address => bytes32[]) public makerPositions;
    mapping(address => mapping(bytes32 => uint256)) internal _posIdx;

    /// @notice What token backs each level (written once on first quote)
    mapping(bytes32 => address) public levelSellToken;

    /// @notice Whether a level's sellToken is a Greek.fi Option — backed by collateral balance
    mapping(bytes32 => bool) public levelIsOption;

    /// @notice Bitmap + bestTick for price discovery
    mapping(bytes32 => uint256) public bitmap;
    mapping(bytes32 => int24) public bestTick;

    int24 internal constant NO_TICK = type(int24).min;
    uint256 internal constant PRECISION = 1e18;

    // ============================================================
    //                          EVENTS
    // ============================================================

    event Deposit(address indexed maker, address indexed token, uint256 amount);
    event Withdraw(address indexed maker, address indexed token, uint256 amount);
    event Swap(address indexed taker, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);

    error InsufficientBalance();
    error InsufficientOutput();
    error ZeroAmount();
    error InvalidTick();
    error NoLiquidity();
    error SameToken();
    error TransferFailed();

    // ============================================================
    //                      OPTION SUPPORT SETUP
    // ============================================================

    /// @notice One-time setup to enable auto-mint delivery of option tokens on swap.
    /// @dev Permissionless + idempotent. Must be called once per (factory, collateral) pair
    ///      before any option-backed quote is posted. Approves the factory to pull collateral
    ///      via standard ERC20 + factory's internal allowance, and opts the book into
    ///      auto-mint/redeem. On fill, _transferOut calls `Option.transfer`, which auto-mints
    ///      options from the book's pooled collateral and delivers them to the taker.
    function enableOptionSupport(address optionToken) external {
        address col = IOption2(optionToken).collateral();
        address fac = IOption2(optionToken).factory();
        IFactorySetup(fac).enableAutoMintRedeem(true);
        IFactorySetup(fac).approve(col, type(uint256).max);
        // Standard ERC20 approval of collateral to factory (for factory.transferFrom during auto-mint)
        (bool ok, bytes memory ret) = col.call(abi.encodeWithSignature("approve(address,uint256)", fac, type(uint256).max));
        if (!ok || (ret.length > 0 && !abi.decode(ret, (bool)))) revert TransferFailed();
    }

    // ============================================================
    //                      DEPOSIT / WITHDRAW
    // ============================================================

    function deposit(address token, uint256 amount) external lock {
        if (amount == 0) revert ZeroAmount();
        _transferIn(token, msg.sender, amount);
        balances[msg.sender][token] += amount;
        emit Deposit(msg.sender, token, amount);
    }

    function withdraw(address token, uint256 amount) external lock {
        if (amount == 0) revert ZeroAmount();
        if (balances[msg.sender][token] < amount) revert InsufficientBalance();

        // Clear any commitments that would exceed remaining balance
        uint256 remaining = balances[msg.sender][token] - amount;
        _trimCommitments(msg.sender, token, remaining);

        balances[msg.sender][token] = remaining;
        _transferOut(token, msg.sender, amount);
        emit Withdraw(msg.sender, token, amount);
    }

    // ============================================================
    //                      QUOTE / CANCEL / REQUOTE
    // ============================================================

    function quote(address sellToken, address buyToken, int24 tick, uint256 amount, bool isOption) external lock {
        _quote(msg.sender, sellToken, buyToken, tick, amount, isOption);
    }

    function cancel(address sellToken, address buyToken, int24 tick) external lock {
        _cancel(msg.sender, sellToken, buyToken, tick);
    }

    function requote(address sellToken, address buyToken, int24 oldTick, int24 newTick, uint256 amount, bool isOption) external lock {
        _cancel(msg.sender, sellToken, buyToken, oldTick);
        _quote(msg.sender, sellToken, buyToken, newTick, amount, isOption);
    }

    // ============================================================
    //                           SWAP
    // ============================================================

    function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minOut) external lock {
        if (amountIn == 0) revert ZeroAmount();

        bytes32 pk = _pairKey(tokenOut, tokenIn);
        int24 current = bestTick[pk];
        if (current == NO_TICK) revert NoLiquidity();

        uint256 totalOut;
        uint256 remainingIn = amountIn;

        while (remainingIn > 0 && current != NO_TICK) {
            (uint256 filled, uint256 spent) = _fillLevel(tokenOut, tokenIn, current, remainingIn);
            totalOut += filled;
            remainingIn -= spent;

            if (remainingIn == 0 || spent == 0) break;

            current = _nextTick(tokenOut, tokenIn, current);
            if (current == NO_TICK) break;
        }

        _refreshBestTick(tokenOut, tokenIn);

        if (totalOut < minOut) revert InsufficientOutput();
        if (totalOut == 0) revert NoLiquidity();

        uint256 actualIn = amountIn - remainingIn;
        _transferIn(tokenIn, msg.sender, actualIn);
        _transferOut(tokenOut, msg.sender, totalOut);

        emit Swap(msg.sender, tokenIn, tokenOut, actualIn, totalOut);
    }

    // ============================================================
    //                        VIEW FUNCTIONS
    // ============================================================

    function tickToPrice(int24 tick) external pure returns (uint256) {
        return _tickToPrice(tick);
    }

    function levelId(address sellToken, address buyToken, int24 tick) external pure returns (bytes32) {
        return _levelId(sellToken, buyToken, tick);
    }

    function getBestTick(address sellToken, address buyToken) external view returns (int24, bool) {
        int24 bt = bestTick[_pairKey(sellToken, buyToken)];
        return (bt, bt != NO_TICK);
    }

    function getPositions(address maker) external view returns (bytes32[] memory) {
        return makerPositions[maker];
    }

    function getLevelMakers(bytes32 lid) external view returns (address[] memory) {
        return levelMakers[lid];
    }

    /// @notice Actual available at a level — checks each maker's real balance
    function getLevelAvailable(address sellToken, address buyToken, int24 tick) external view returns (uint256) {
        return _availableAt(sellToken, buyToken, tick);
    }

    function getBook(address sellToken, address buyToken, uint256 n) external view returns (int24[] memory ticks, uint256[] memory amounts) {
        ticks = new int24[](n);
        amounts = new uint256[](n);

        int24 current = bestTick[_pairKey(sellToken, buyToken)];
        if (current == NO_TICK) {
            assembly { mstore(ticks, 0) mstore(amounts, 0) }
            return (ticks, amounts);
        }

        uint256 found;
        int16 startWord = int16(current >> 8) - 1;

        for (int16 w = startWord; found < n; w++) {
            if (w > 1733) break;
            uint256 word = bitmap[_bitmapKey(sellToken, buyToken, w)];
            while (word != 0 && found < n) {
                uint8 bit = _lsb(word);
                int24 tick = int24(w) * 256 + int24(uint24(bit));
                word &= word - 1;

                uint256 avail = _availableAt(sellToken, buyToken, tick);
                if (avail > 0) {
                    ticks[found] = tick;
                    amounts[found] = avail;
                    found++;
                }
            }
        }
        assembly { mstore(ticks, found) mstore(amounts, found) }
    }

    // ============================================================
    //                     INTERNAL: TRIM ON WITHDRAW
    // ============================================================

    /// @notice Trim commitments for a token down to remaining balance
    function _trimCommitments(address maker, address token, uint256 remaining) internal {
        bytes32[] storage positions = makerPositions[maker];
        for (uint256 i = positions.length; i > 0; i--) {
            bytes32 lid = positions[i - 1];
            address sellTok = levelSellToken[lid];
            address backing = levelIsOption[lid] ? IOption2(sellTok).collateral() : sellTok;
            if (backing != token) continue;

            uint256 committed = commitments[maker][lid];
            if (committed == 0) continue;
            if (committed <= remaining) continue;

            // Trim to remaining, or cancel entirely
            if (remaining > 0) {
                commitments[maker][lid] = remaining;
            } else {
                commitments[maker][lid] = 0;
                _removeMakerFromLevel(maker, lid);
                // Safe to remove while iterating backwards
                uint256 last = positions.length - 1;
                if (i - 1 != last) {
                    positions[i - 1] = positions[last];
                    _posIdx[maker][positions[i - 1]] = i - 1;
                }
                positions.pop();
                delete _posIdx[maker][lid];
            }
        }
    }

    // ============================================================
    //                     INTERNAL: QUOTE / CANCEL
    // ============================================================

    function _quote(address maker, address sellToken, address buyToken, int24 tick, uint256 amount, bool isOption) internal {
        if (amount == 0) revert ZeroAmount();
        if (sellToken == address(0) || buyToken == address(0)) revert ZeroAmount();
        if (sellToken == buyToken) revert SameToken();
        if (tick < -443636 || tick > 443636) revert InvalidTick();

        address checkToken = isOption ? IOption2(sellToken).collateral() : sellToken;
        if (balances[maker][checkToken] < amount) revert InsufficientBalance();

        bytes32 lid = _levelId(sellToken, buyToken, tick);
        bool isNew = commitments[maker][lid] == 0;
        commitments[maker][lid] = amount;
        if (levelSellToken[lid] == address(0)) {
            levelSellToken[lid] = sellToken;
            levelIsOption[lid] = isOption;
        }

        if (isNew) {
            _addMakerToLevel(maker, lid);
            _addMakerPosition(maker, lid);
        }

        _setBit(sellToken, buyToken, tick);
        _updateBestTickOnAdd(sellToken, buyToken, tick);
    }

    function _cancel(address maker, address sellToken, address buyToken, int24 tick) internal {
        bytes32 lid = _levelId(sellToken, buyToken, tick);
        if (commitments[maker][lid] == 0) return;

        commitments[maker][lid] = 0;
        _removeMakerFromLevel(maker, lid);
        _removeMakerPosition(maker, lid);

        if (levelMakers[lid].length == 0) {
            _clearBit(sellToken, buyToken, tick);
            _updateBestTickAfterRemoval(sellToken, buyToken, tick);
        }
    }

    // ============================================================
    //                     INTERNAL: FILL
    // ============================================================

    function _fillLevel(address sellToken, address buyToken, int24 tick, uint256 maxIn) internal returns (uint256 fillOut, uint256 fillIn) {
        bytes32 lid = _levelId(sellToken, buyToken, tick);
        address[] storage makers = levelMakers[lid];
        if (makers.length == 0) return (0, 0);

        uint256 price = _tickToPrice(tick);
        uint256 remaining = (maxIn * PRECISION) / price;
        address backing = levelIsOption[lid] ? IOption2(sellToken).collateral() : sellToken;

        // Fill pass
        for (uint256 i = 0; i < makers.length && remaining > 0; i++) {
            uint256 take = commitments[makers[i]][lid];
            if (take == 0) continue;
            if (take > remaining) take = remaining;
            if (take > balances[makers[i]][backing]) take = balances[makers[i]][backing];
            if (take == 0) continue;

            balances[makers[i]][backing] -= take;
            balances[makers[i]][buyToken] += (take * price) / PRECISION;
            commitments[makers[i]][lid] -= take;

            remaining -= take;
            fillOut += take;
        }

        fillIn = (fillOut * price) / PRECISION;

        // Sweep pass — remove drained makers (iterate backwards for safe swap-and-pop).
        // Capture makers[i-1] into a local because _removeMakerFromLevel swap-and-pops,
        // mutating the array underneath. Re-reading after the pop is either OOB (single
        // maker → length 0) or reads the moved-in element (swap put a different maker there).
        for (uint256 i = makers.length; i > 0; i--) {
            address m = makers[i - 1];
            if (commitments[m][lid] == 0) {
                _removeMakerFromLevel(m, lid);
                _removeMakerPosition(m, lid);
            }
        }

        if (makers.length == 0) {
            _clearBit(sellToken, buyToken, tick);
        }
    }

    // ============================================================
    //                     INTERNAL: ARRAY MANAGEMENT
    // ============================================================

    function _addMakerToLevel(address maker, bytes32 lid) internal {
        _makerIdx[lid][maker] = levelMakers[lid].length;
        levelMakers[lid].push(maker);
    }

    function _removeMakerFromLevel(address maker, bytes32 lid) internal {
        address[] storage arr = levelMakers[lid];
        uint256 idx = _makerIdx[lid][maker];
        uint256 last = arr.length - 1;
        if (idx != last) {
            arr[idx] = arr[last];
            _makerIdx[lid][arr[idx]] = idx;
        }
        arr.pop();
        delete _makerIdx[lid][maker];
    }

    function _addMakerPosition(address maker, bytes32 lid) internal {
        _posIdx[maker][lid] = makerPositions[maker].length;
        makerPositions[maker].push(lid);
    }

    function _removeMakerPosition(address maker, bytes32 lid) internal {
        bytes32[] storage arr = makerPositions[maker];
        uint256 idx = _posIdx[maker][lid];
        uint256 last = arr.length - 1;
        if (idx != last) {
            arr[idx] = arr[last];
            _posIdx[maker][arr[idx]] = idx;
        }
        arr.pop();
        delete _posIdx[maker][lid];
    }

    // ============================================================
    //                     INTERNAL: VIEWS
    // ============================================================

    function _availableAt(address sellToken, address buyToken, int24 tick) internal view returns (uint256 total) {
        bytes32 lid = _levelId(sellToken, buyToken, tick);
        address[] storage makers = levelMakers[lid];
        address backing = levelIsOption[lid] ? IOption2(sellToken).collateral() : sellToken;
        for (uint256 i = 0; i < makers.length; i++) {
            uint256 c = commitments[makers[i]][lid];
            uint256 b = balances[makers[i]][backing];
            total += c < b ? c : b;
        }
    }

    // ============================================================
    //                     INTERNAL: TICK MATH
    // ============================================================

    function _tickToPrice(int24 tick) internal pure returns (uint256) {
        uint256 sqrtP = uint256(TickMath.getSqrtPriceAtTick(tick));
        return (sqrtP * sqrtP * 1e18) >> 192;
    }

    function _levelId(address a, address b, int24 tick) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(a, b, tick));
    }

    function _pairKey(address a, address b) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(a, b));
    }

    function _bitmapKey(address a, address b, int16 w) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(a, b, w));
    }

    function _tickPos(int24 tick) internal pure returns (int16 w, uint8 b) {
        w = int16(tick >> 8);
        b = uint8(uint24(tick) & 0xff);
    }

    // ============================================================
    //                     INTERNAL: BITMAP
    // ============================================================

    function _setBit(address a, address b, int24 tick) internal {
        (int16 w, uint8 bp) = _tickPos(tick);
        bytes32 key = _bitmapKey(a, b, w);
        uint256 mask = 1 << bp;
        uint256 word = bitmap[key];
        if (word & mask == 0) bitmap[key] = word | mask;
    }

    function _clearBit(address a, address b, int24 tick) internal {
        (int16 w, uint8 bp) = _tickPos(tick);
        bytes32 key = _bitmapKey(a, b, w);
        uint256 mask = 1 << bp;
        uint256 word = bitmap[key];
        if (word & mask != 0) bitmap[key] = word & ~mask;
    }

    function _nextTick(address a, address b, int24 from) internal view returns (int24) {
        int24 next = from + 1;
        (int16 w, uint8 bp) = _tickPos(next);
        uint256 word = bitmap[_bitmapKey(a, b, w)] & ~((1 << uint256(bp)) - 1);
        if (word != 0) return int24(int16(w)) * 256 + int24(uint24(_lsb(word)));

        for (int16 i = w + 1; i <= w + 10; i++) {
            word = bitmap[_bitmapKey(a, b, i)];
            if (word != 0) return int24(int16(i)) * 256 + int24(uint24(_lsb(word)));
        }
        return NO_TICK;
    }

    // ============================================================
    //                     INTERNAL: BEST TICK
    // ============================================================

    function _updateBestTickOnAdd(address a, address b, int24 tick) internal {
        bytes32 pk = _pairKey(a, b);
        int24 cur = bestTick[pk];
        if (cur == NO_TICK || cur == 0 || tick < cur) bestTick[pk] = tick;
    }

    function _updateBestTickAfterRemoval(address a, address b, int24 tick) internal {
        bytes32 pk = _pairKey(a, b);
        if (bestTick[pk] != tick) return;

        (int16 w, uint8 bp) = _tickPos(tick);
        uint256 word = bitmap[_bitmapKey(a, b, w)] & ~((1 << (uint256(bp) + 1)) - 1);
        if (word != 0) { bestTick[pk] = int24(int16(w)) * 256 + int24(uint24(_lsb(word))); return; }

        word = bitmap[_bitmapKey(a, b, w + 1)];
        if (word != 0) { bestTick[pk] = int24(int16(w + 1)) * 256 + int24(uint24(_lsb(word))); return; }

        bestTick[pk] = NO_TICK;
    }

    function _refreshBestTick(address a, address b) internal {
        bytes32 pk = _pairKey(a, b);
        int24 cur = bestTick[pk];
        if (cur == NO_TICK) return;
        if (levelMakers[_levelId(a, b, cur)].length > 0) return;
        _updateBestTickAfterRemoval(a, b, cur);
    }

    function _lsb(uint256 x) internal pure returns (uint8 r) {
        assembly ("memory-safe") {
            x := and(x, sub(0, x))
            r := sub(255, clz(x))
        }
    }

    // ============================================================
    //                     INTERNAL: TRANSFERS
    // ============================================================

    function _transferIn(address token, address from, uint256 amount) internal {
        (bool ok, bytes memory ret) = token.call(abi.encodeCall(IToken2.transferFrom, (from, address(this), amount)));
        if (!ok || (ret.length > 0 && !abi.decode(ret, (bool)))) revert TransferFailed();
    }

    function _transferOut(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory ret) = token.call(abi.encodeCall(IToken2.transfer, (to, amount)));
        if (!ok || (ret.length > 0 && !abi.decode(ret, (bool)))) revert TransferFailed();
    }
}
