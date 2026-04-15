// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { TickMath } from "./libraries/TickMath.sol";

interface IToken {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IOption {
    function collateral() external view returns (address);
    function factory() external view returns (address);
}

interface INuFactorySetup {
    function enableAutoMintRedeem(bool enabled) external;
    function approve(address token, uint256 amount) external;
}

/// @title NuAMM v2 - on-chain programmable liquidity book
/// @notice Makers deposit tokens, quote at tick-based price levels, takers sweep best-to-worst.
///         Pro-rata fills within each level. Lazy settlement via accumulators.
///         Prices use log-spaced ticks (1.0001^tick) for uniform 1-bip resolution at all scales.
contract NuAMMv2 {
    // ============================================================
    //                       REENTRANCY LOCK
    // ============================================================

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

    struct Level {
        uint128 balance;
        uint128 totalShares;
        uint256 accPerShare;
    }

    struct Position {
        uint256 shares;
        uint256 lastAccPerShare;
        uint32 arrayIndex;
    }

    mapping(address => mapping(address => uint256)) public balances;
    mapping(bytes32 => Level) public levels;
    mapping(address => mapping(bytes32 => Position)) public positions;
    mapping(bytes32 => uint256) public bitmap;
    mapping(address => bytes32[]) public makerPositions;

    /// @notice Best (lowest) tick with liquidity per pair.
    ///         NO_TICK sentinel means no known liquidity.
    mapping(bytes32 => int24) public bestTick;

    int24 internal constant NO_TICK = type(int24).min; // -8388608, outside valid range

    uint256 internal constant ACC_PRECISION = 1e18;

    // ============================================================
    //                          EVENTS
    // ============================================================

    event Deposit(address indexed maker, address indexed token, uint256 amount);
    event Withdraw(address indexed maker, address indexed token, uint256 amount);
    event Swap(address indexed taker, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);

    error InsufficientBalance();
    error InsufficientOutput();
    error NoPosition();
    error ZeroAmount();
    error InvalidTick();
    error NoLiquidity();
    error LevelOverflow();
    error TransferFailed();
    error SameToken();
    error ArrayLengthMismatch();

    // ============================================================
    //                      OPTION SUPPORT SETUP
    // ============================================================

    /// @notice One-time setup to enable auto-mint delivery of option tokens on swap.
    /// @dev Permissionless + idempotent. Approves factory to pull collateral via standard
    ///      ERC20 + factory's internal allowance, and opts the book into auto-mint/redeem.
    ///      Must be called once per (factory, collateral) pair before any option-backed quote.
    function enableOptionSupport(address optionToken) external {
        address col = IOption(optionToken).collateral();
        address fac = IOption(optionToken).factory();
        INuFactorySetup(fac).enableAutoMintRedeem(true);
        INuFactorySetup(fac).approve(col, type(uint256).max);
        (bool ok, bytes memory ret) =
            col.call(abi.encodeWithSignature("approve(address,uint256)", fac, type(uint256).max));
        if (!ok || (ret.length > 0 && !abi.decode(ret, (bool)))) revert TransferFailed();
    }

    // ============================================================
    //                      DEPOSIT / WITHDRAW
    // ============================================================

    function deposit(address token, uint256 amount) external lock {
        if (amount == 0) revert ZeroAmount();
        _safeTransferFrom(token, msg.sender, address(this), amount);
        balances[msg.sender][token] += amount;
        emit Deposit(msg.sender, token, amount);
    }

    function withdraw(address token, uint256 amount) external lock {
        if (amount == 0) revert ZeroAmount();
        if (balances[msg.sender][token] < amount) revert InsufficientBalance();
        balances[msg.sender][token] -= amount;
        _safeTransfer(token, msg.sender, amount);
        emit Withdraw(msg.sender, token, amount);
    }

    // ============================================================
    //                      QUOTE / CANCEL / REQUOTE
    // ============================================================

    function quote(address sellToken, address buyToken, int24 tick, uint256 amount, bool isOption) external lock {
        uint256 remaining = _maybeCross(msg.sender, sellToken, buyToken, tick, amount);
        if (remaining > 0) {
            _quote(msg.sender, sellToken, buyToken, tick, remaining, isOption);
        }
    }

    function cancel(address sellToken, address buyToken, int24 tick, bool isOption) external lock {
        _cancel(msg.sender, sellToken, buyToken, tick, isOption);
    }

    function requote(address sellToken, address buyToken, int24 oldTick, int24 newTick, uint256 amount, bool isOption)
        external
        lock
    {
        _cancel(msg.sender, sellToken, buyToken, oldTick, isOption);
        uint256 remaining = _maybeCross(msg.sender, sellToken, buyToken, newTick, amount);
        if (remaining > 0) {
            _quote(msg.sender, sellToken, buyToken, newTick, remaining, isOption);
        }
    }

    function cancelBatch(
        address[] calldata sellTokens,
        address[] calldata buyTokens,
        int24[] calldata ticks,
        bool[] calldata isOptions
    ) external lock {
        if (
            sellTokens.length != buyTokens.length || sellTokens.length != ticks.length
                || sellTokens.length != isOptions.length
        ) revert ArrayLengthMismatch();
        for (uint256 i = 0; i < sellTokens.length; i++) {
            bytes32 lid = _levelId(sellTokens[i], buyTokens[i], ticks[i]);
            Position storage pos = positions[msg.sender][lid];
            if (pos.shares == 0) continue;
            _cancel(msg.sender, sellTokens[i], buyTokens[i], ticks[i], isOptions[i]);
        }
    }

    // ============================================================
    //                           SWAP
    // ============================================================

    /// @notice Taker swaps by walking the book automatically from bestTick
    /// @param tokenIn Token the taker sends
    /// @param tokenOut Token the taker wants
    /// @param amountIn Amount of tokenIn the taker sends
    /// @param minOut Minimum tokenOut the taker accepts (slippage protection)
    function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minOut) external lock {
        if (amountIn == 0) revert ZeroAmount();

        // Makers sell tokenOut, want tokenIn
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

            int24 next = _nextTickInWord(tokenOut, tokenIn, current);
            if (next == NO_TICK) break;
            current = next;
        }

        // Update bestTick — current is where we stopped or last filled
        _refreshBestTick(tokenOut, tokenIn);

        if (totalOut < minOut) revert InsufficientOutput();
        if (totalOut == 0) revert NoLiquidity();

        uint256 actualIn = amountIn - remainingIn;
        _safeTransferFrom(tokenIn, msg.sender, address(this), actualIn);
        _safeTransfer(tokenOut, msg.sender, totalOut);

        emit Swap(msg.sender, tokenIn, tokenOut, actualIn, totalOut);
    }

    // ============================================================
    //                         SETTLE
    // ============================================================

    function settle(address maker, address[] calldata sellTokens, address[] calldata buyTokens, int24[] calldata ticks)
        external
        lock
    {
        if (sellTokens.length != buyTokens.length || sellTokens.length != ticks.length) revert ArrayLengthMismatch();
        for (uint256 i = 0; i < sellTokens.length; i++) {
            bytes32 lid = _levelId(sellTokens[i], buyTokens[i], ticks[i]);
            _settle(maker, levels[lid], positions[maker][lid], buyTokens[i]);
        }
    }

    function settleAndWithdraw(
        address maker,
        address token,
        address[] calldata sellTokens,
        address[] calldata buyTokens,
        int24[] calldata ticks
    ) external lock {
        if (sellTokens.length != buyTokens.length || sellTokens.length != ticks.length) {
            revert ArrayLengthMismatch();
        }
        for (uint256 i = 0; i < sellTokens.length; i++) {
            if (buyTokens[i] != token) continue;
            bytes32 lid = _levelId(sellTokens[i], buyTokens[i], ticks[i]);
            _settle(maker, levels[lid], positions[maker][lid], buyTokens[i]);
        }

        uint256 bal = balances[maker][token];
        if (bal > 0) {
            balances[maker][token] = 0;
            _safeTransfer(token, maker, bal);
            emit Withdraw(maker, token, bal);
        }
    }

    // ============================================================
    //                        VIEW FUNCTIONS
    // ============================================================

    function levelId(address sellToken, address buyToken, int24 tick) external pure returns (bytes32) {
        return _levelId(sellToken, buyToken, tick);
    }

    /// @notice Convert a tick to its actual price (1.0001^tick) scaled by 1e18
    function tickToPrice(int24 tick) external pure returns (uint256) {
        return _tickToPrice(tick);
    }

    /// @notice Get the closest tick for a desired price
    function priceToTick(uint256 price) external pure returns (int24) {
        // price is scaled by 1e18. Convert to sqrtPriceX96.
        // price = sqrtP^2 / 2^192 * 1e18
        // sqrtP = sqrt(price * 2^192 / 1e18)
        // Approximate: use TickMath.getTickAtSqrtPrice
        // sqrtPriceX96 = sqrt(price) * 2^96 / sqrt(1e18)
        // sqrt(1e18) = 1e9
        uint256 sqrtPrice = _sqrt(price);
        uint160 sqrtPriceX96 = uint160((sqrtPrice << 96) / 1e9);
        if (sqrtPriceX96 < TickMath.MIN_SQRT_PRICE) sqrtPriceX96 = TickMath.MIN_SQRT_PRICE;
        if (sqrtPriceX96 >= TickMath.MAX_SQRT_PRICE) sqrtPriceX96 = TickMath.MAX_SQRT_PRICE - 1;
        return TickMath.getTickAtSqrtPrice(sqrtPriceX96);
    }

    function pendingProceeds(address maker, address sellToken, address buyToken, int24 tick)
        external
        view
        returns (uint256)
    {
        bytes32 lid = _levelId(sellToken, buyToken, tick);
        Level storage level = levels[lid];
        Position storage pos = positions[maker][lid];
        if (pos.shares == 0) return 0;
        uint256 accDiff = level.accPerShare - pos.lastAccPerShare;
        return (pos.shares * accDiff) / ACC_PRECISION;
    }

    function makerBalanceAtLevel(address maker, address sellToken, address buyToken, int24 tick)
        external
        view
        returns (uint256)
    {
        bytes32 lid = _levelId(sellToken, buyToken, tick);
        Level storage level = levels[lid];
        Position storage pos = positions[maker][lid];
        if (pos.shares == 0 || level.totalShares == 0) return 0;
        return (pos.shares * uint256(level.balance)) / uint256(level.totalShares);
    }

    function hasLiquidity(address sellToken, address buyToken, int24 tick) external view returns (bool) {
        return _getBit(sellToken, buyToken, tick);
    }

    /// @notice Get the best ask (lowest tick) for a pair
    /// @notice Returns (bestTick, isActive). NO_TICK means no known liquidity.
    function getBestTick(address sellToken, address buyToken) external view returns (int24, bool) {
        bytes32 pairKey = _pairKey(sellToken, buyToken);
        int24 bt = bestTick[pairKey];
        return (bt, bt != NO_TICK);
    }

    /// @notice Check if a quote at tick would cross the opposite side
    function wouldCross(address sellToken, address buyToken, int24 tick) external view returns (bool) {
        bytes32 oppPairKey = _pairKey(buyToken, sellToken);
        int24 bt = bestTick[oppPairKey];
        if (bt == NO_TICK) return false;
        return bt <= -tick;
    }

    /// @notice Return up to N ticks starting from bestTick
    function getBook(address sellToken, address buyToken, uint256 n)
        external
        view
        returns (int24[] memory ticks, uint128[] memory amounts)
    {
        ticks = new int24[](n);
        amounts = new uint128[](n);

        int24 current = bestTick[_pairKey(sellToken, buyToken)];
        if (current == NO_TICK) {
            assembly {
                mstore(ticks, 0)
                mstore(amounts, 0)
            }
            return (ticks, amounts);
        }

        uint256 found;

        // Start one word before bestTick for buffer
        int16 startWord = int16(current >> 8) - 1;

        for (int16 w = startWord; found < n; w++) {
            if (w > 1733) break; // max word for tick 443636
            uint256 word = bitmap[_bitmapKey(sellToken, buyToken, w)];

            while (word != 0 && found < n) {
                uint8 bit = _lsb(word);
                int24 tick = int24(w) * 256 + int24(uint24(bit));
                word &= word - 1;

                uint128 bal = levels[_levelId(sellToken, buyToken, tick)].balance;
                if (bal > 0) {
                    ticks[found] = tick;
                    amounts[found] = bal;
                    found++;
                }
            }
        }

        assembly {
            mstore(ticks, found)
            mstore(amounts, found)
        }
    }

    function getPositions(address maker) external view returns (bytes32[] memory) {
        return makerPositions[maker];
    }

    function getPositionCount(address maker) external view returns (uint256) {
        return makerPositions[maker].length;
    }

    // ============================================================
    //                     INTERNAL: OPTION HELPERS
    // ============================================================

    function _optionCollateral(address token) internal view returns (address) {
        address col = IOption(token).collateral();
        if (col == address(0)) revert ZeroAmount();
        return col;
    }

    // ============================================================
    //                     INTERNAL: CROSSING FILL
    // ============================================================

    /// @notice Fill a single level, returns (amountOut, amountIn consumed)
    function _fillLevel(address sellToken, address buyToken, int24 tick, uint256 maxIn)
        internal
        returns (uint256 fillOut, uint256 fillIn)
    {
        bytes32 lid = _levelId(sellToken, buyToken, tick);
        Level storage level = levels[lid];
        if (level.balance == 0) return (0, 0);

        uint256 price = _tickToPrice(tick);
        uint256 maxOut = uint256(level.balance);
        uint256 wantOut = (maxIn * ACC_PRECISION) / price;

        if (wantOut >= maxOut) {
            fillOut = maxOut;
            fillIn = (maxOut * price) / ACC_PRECISION;
        } else {
            fillOut = wantOut;
            fillIn = maxIn;
        }

        if (fillOut == 0) return (0, 0);

        level.accPerShare += (fillIn * ACC_PRECISION) / uint256(level.totalShares);
        level.balance -= uint128(fillOut);

        if (level.balance == 0) {
            _clearBit(sellToken, buyToken, tick);
        }
    }

    /// @notice Quick crossing check + fill if needed
    function _maybeCross(address maker, address sellToken, address buyToken, int24 makerTick, uint256 amount)
        internal
        returns (uint256)
    {
        bytes32 oppPairKey = _pairKey(buyToken, sellToken);
        int24 oppBest = bestTick[oppPairKey];
        if (oppBest == NO_TICK || oppBest > -makerTick) {
            return amount;
        }
        return _fillCrossing(maker, sellToken, buyToken, makerTick, amount);
    }

    /// @notice Fill against crossing levels on the opposite side of the book
    function _fillCrossing(address maker, address sellToken, address buyToken, int24 makerTick, uint256 amount)
        internal
        returns (uint256 remaining)
    {
        // Cap amount to available balance
        uint256 available = balances[maker][sellToken];
        if (amount > available) amount = available;

        remaining = amount;
        int24 maxCrossTick = -makerTick;
        bytes32 oppPairKey = _pairKey(buyToken, sellToken);
        int24 currentTick = int24(bestTick[oppPairKey]);

        while (remaining > 0 && currentTick <= maxCrossTick) {
            (uint256 fillOut, uint256 fillIn) = _fillLevel(buyToken, sellToken, currentTick, remaining);

            if (fillOut > 0) {
                balances[maker][buyToken] += fillOut;
                remaining -= fillIn;
            }

            if (remaining == 0 || fillIn == 0) break;

            int24 next = _nextTickInWord(buyToken, sellToken, currentTick);
            if (next == NO_TICK || next > maxCrossTick) break;
            currentTick = next;
        }

        // Update bestTick if anything was filled
        if (remaining < amount) {
            _refreshBestTick(buyToken, sellToken);
        }

        uint256 spent = amount - remaining;
        if (spent > 0) {
            balances[maker][sellToken] -= spent;
        }
    }

    // ============================================================
    //                     INTERNAL: QUOTE / CANCEL
    // ============================================================

    function _quote(address maker, address sellToken, address buyToken, int24 tick, uint256 amount, bool isOption)
        internal
    {
        if (amount == 0) revert ZeroAmount();
        if (sellToken == address(0) || buyToken == address(0)) revert ZeroAmount();
        if (sellToken == buyToken) revert SameToken();
        if (tick < -443636 || tick > 443636) revert InvalidTick();

        address deductToken = isOption ? _optionCollateral(sellToken) : sellToken;
        if (balances[maker][deductToken] < amount) revert InsufficientBalance();

        bytes32 lid = _levelId(sellToken, buyToken, tick);
        Level storage level = levels[lid];
        Position storage pos = positions[maker][lid];

        _settle(maker, level, pos, buyToken);

        balances[maker][deductToken] -= amount;

        uint256 newShares;
        if (level.totalShares == 0 || level.balance == 0) {
            newShares = amount;
        } else {
            newShares = (amount * uint256(level.totalShares)) / uint256(level.balance);
        }

        if (newShares == 0) revert ZeroAmount();

        if (amount > type(uint128).max - level.balance) revert LevelOverflow();
        if (newShares > type(uint128).max - level.totalShares) revert LevelOverflow();
        level.balance += uint128(amount);
        level.totalShares += uint128(newShares);

        bool isNew = pos.shares == 0;
        pos.shares += newShares;
        pos.lastAccPerShare = level.accPerShare;

        if (isNew) {
            pos.arrayIndex = uint32(makerPositions[maker].length);
            makerPositions[maker].push(lid);
        }

        _setBit(sellToken, buyToken, tick);
        _updateBestTickOnAdd(sellToken, buyToken, tick);
    }

    function _cancel(address maker, address sellToken, address buyToken, int24 tick, bool isOption) internal {
        bytes32 lid = _levelId(sellToken, buyToken, tick);
        Level storage level = levels[lid];
        Position storage pos = positions[maker][lid];
        if (pos.shares == 0) revert NoPosition();

        _settle(maker, level, pos, buyToken);

        if (pos.shares > type(uint128).max) revert LevelOverflow();
        uint128 shares = uint128(pos.shares);
        uint256 returned = (uint256(shares) * uint256(level.balance)) / uint256(level.totalShares);

        level.balance -= uint128(returned);
        level.totalShares -= shares;

        _removeFromArray(maker, lid, pos);

        delete positions[maker][lid];

        address returnToken = isOption ? _optionCollateral(sellToken) : sellToken;
        balances[maker][returnToken] += returned;

        if (level.totalShares == 0) {
            _clearBit(sellToken, buyToken, tick);
            _updateBestTickAfterRemoval(sellToken, buyToken, tick);
        }
    }

    // ============================================================
    //                     INTERNAL: ARRAY MGMT
    // ============================================================

    function _removeFromArray(address maker, bytes32 lid, Position storage pos) internal {
        bytes32[] storage arr = makerPositions[maker];
        uint256 idx = pos.arrayIndex;
        uint256 lastIdx = arr.length - 1;

        if (idx != lastIdx) {
            bytes32 lastLid = arr[lastIdx];
            arr[idx] = lastLid;
            positions[maker][lastLid].arrayIndex = uint32(idx);
        }
        arr.pop();
    }

    // ============================================================
    //                     INTERNAL: SETTLE
    // ============================================================

    function _settle(address maker, Level storage level, Position storage pos, address buyToken) internal {
        if (pos.shares == 0) return;
        uint256 accDiff = level.accPerShare - pos.lastAccPerShare;
        if (accDiff > 0) {
            uint256 owed = (pos.shares * accDiff) / ACC_PRECISION;
            if (owed > 0) {
                balances[maker][buyToken] += owed;
            }
        }
        pos.lastAccPerShare = level.accPerShare;
    }

    // ============================================================
    //                     INTERNAL: TICK MATH
    // ============================================================

    /// @notice Convert tick to price scaled by 1e18
    /// @dev price = (sqrtPriceX96)^2 / 2^192 * 1e18
    function _tickToPrice(int24 tick) internal pure returns (uint256) {
        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(tick);
        uint256 sqrtP = uint256(sqrtPriceX96);
        // sqrtPriceX96 = sqrt(price) * 2^96
        // price = sqrtP^2 / 2^192
        // scaled by 1e18: price = sqrtP^2 * 1e18 / 2^192
        // To avoid overflow: (sqrtP * sqrtP / 2^64) * 1e18 / 2^128
        return (sqrtP * sqrtP * 1e18) >> 192;
    }

    /// @dev Integer square root (Babylonian method)
    function _sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;
        y = x;
        uint256 z = (x + 1) / 2;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }

    // ============================================================
    //                     INTERNAL: BEST TICK TRACKING
    // ============================================================

    function _pairKey(address sellToken, address buyToken) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(sellToken, buyToken));
    }

    /// @notice Find next active tick, scanning up to 10 bitmap words (~2560 ticks)
    function _nextTickInWord(address sellToken, address buyToken, int24 fromTick) internal view returns (int24) {
        int24 next = fromTick + 1;
        (int16 wordPos, uint8 bitPos) = _tickPosition(next);

        // Check current word (masked)
        uint256 word = bitmap[_bitmapKey(sellToken, buyToken, wordPos)] & ~((1 << uint256(bitPos)) - 1);
        if (word != 0) {
            return int24(int16(wordPos)) * 256 + int24(uint24(_lsb(word)));
        }

        // Scan up to 10 more words
        for (int16 w = wordPos + 1; w <= wordPos + 10; w++) {
            word = bitmap[_bitmapKey(sellToken, buyToken, w)];
            if (word != 0) {
                return int24(int16(w)) * 256 + int24(uint24(_lsb(word)));
            }
        }

        return NO_TICK;
    }

    /// @notice Refresh bestTick by scanning from current bestTick
    function _refreshBestTick(address sellToken, address buyToken) internal {
        bytes32 pk = _pairKey(sellToken, buyToken);
        int24 current = bestTick[pk];
        if (current == NO_TICK) return;

        // If current tick still has balance, it's still the best
        bytes32 lid = _levelId(sellToken, buyToken, current);
        if (levels[lid].balance > 0) return;

        // Current was drained — find next
        _updateBestTickAfterRemoval(sellToken, buyToken, current);
    }

    function _updateBestTickOnAdd(address sellToken, address buyToken, int24 tick) internal {
        bytes32 pk = _pairKey(sellToken, buyToken);
        int24 current = bestTick[pk];
        // Uninitialized mapping returns 0. We use bitmap to distinguish
        // "bestTick is actually 0" from "never set". If current is 0 and
        // bitmap has no bit at tick 0, it's uninitialized.
        if (current == NO_TICK || tick < current || (current == 0 && !_getBit(sellToken, buyToken, 0))) {
            bestTick[pk] = tick;
        }
    }

    function _updateBestTickAfterRemoval(address sellToken, address buyToken, int24 removedTick) internal {
        bytes32 pk = _pairKey(sellToken, buyToken);
        if (bestTick[pk] != removedTick) return;

        // The best tick was just emptied — scan bitmap for the next one
        (int16 wordPos, uint8 bitPos) = _tickPosition(removedTick);
        bytes32 key = _bitmapKey(sellToken, buyToken, wordPos);

        // Check remaining bits above removedTick in the same word
        uint256 word = bitmap[key] & ~((1 << (uint256(bitPos) + 1)) - 1);
        if (word != 0) {
            // Found next tick in same word
            uint8 nextBit = _lsb(word);
            bestTick[pk] = int24(int16(wordPos)) * 256 + int24(uint24(nextBit));
            return;
        }

        // Check next word
        word = bitmap[_bitmapKey(sellToken, buyToken, wordPos + 1)];
        if (word != 0) {
            uint8 nextBit = _lsb(word);
            bestTick[pk] = int24(int16(wordPos + 1)) * 256 + int24(uint24(nextBit));
            return;
        }

        // Not nearby — mark inactive. Next quote re-establishes bestTick.
        bestTick[pk] = NO_TICK;
    }

    function _lsb(uint256 x) internal pure returns (uint8 r) {
        assembly ("memory-safe") {
            x := and(x, sub(0, x))
            r := sub(255, clz(x))
        }
    }

    // ============================================================
    //                     INTERNAL: LEVEL ID
    // ============================================================

    function _levelId(address sellToken, address buyToken, int24 tick) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(sellToken, buyToken, tick));
    }

    // ============================================================
    //                     INTERNAL: BITMAP
    // ============================================================

    function _bitmapKey(address sellToken, address buyToken, int16 wordPos) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(sellToken, buyToken, wordPos));
    }

    function _tickPosition(int24 tick) internal pure returns (int16 wordPos, uint8 bitPos) {
        wordPos = int16(tick >> 8);
        bitPos = uint8(uint24(tick) & 0xff);
    }

    function _setBit(address sellToken, address buyToken, int24 tick) internal {
        (int16 wordPos, uint8 bitPos) = _tickPosition(tick);
        bytes32 key = _bitmapKey(sellToken, buyToken, wordPos);
        uint256 mask = 1 << bitPos;
        uint256 word = bitmap[key];
        if (word & mask == 0) {
            bitmap[key] = word | mask;
        }
    }

    function _clearBit(address sellToken, address buyToken, int24 tick) internal {
        (int16 wordPos, uint8 bitPos) = _tickPosition(tick);
        bytes32 key = _bitmapKey(sellToken, buyToken, wordPos);
        uint256 mask = 1 << bitPos;
        uint256 word = bitmap[key];
        if (word & mask != 0) {
            bitmap[key] = word & ~mask;
        }
    }

    function _getBit(address sellToken, address buyToken, int24 tick) internal view returns (bool) {
        (int16 wordPos, uint8 bitPos) = _tickPosition(tick);
        bytes32 key = _bitmapKey(sellToken, buyToken, wordPos);
        return (bitmap[key] & (1 << bitPos)) != 0;
    }

    // ============================================================
    //                     INTERNAL: SAFE TRANSFERS
    // ============================================================

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory ret) = token.call(abi.encodeCall(IToken.transfer, (to, amount)));
        if (!ok || (ret.length > 0 && !abi.decode(ret, (bool)))) revert TransferFailed();
    }

    function _safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        (bool ok, bytes memory ret) = token.call(abi.encodeCall(IToken.transferFrom, (from, to, amount)));
        if (!ok || (ret.length > 0 && !abi.decode(ret, (bool)))) revert TransferFailed();
    }
}
