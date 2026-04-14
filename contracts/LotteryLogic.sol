// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title LotteryLogic
 * @author YieldWin Protocol
 * @notice Library for weighted lottery winner selection.
 *         Derives 5 unique winners from a single Chainlink VRF random seed.
 *         Uses ticket balance as weight (more tickets = higher chance).
 * @dev    Uses Fisher-Yates partial shuffle on a weighted index array.
 *         All logic is pure/view – no state mutations.
 */
library LotteryLogic {

    // ─────────────────────────────────────────────
    //  Types
    // ─────────────────────────────────────────────

    struct DrawState {
        address[] participants;
        uint256[] weights;      // Ticket balance per participant
        uint256   totalWeight;
    }

    // ─────────────────────────────────────────────
    //  Core Selection
    // ─────────────────────────────────────────────

    /**
     * @notice Selects 5 unique winners from the eligible participants array
     *         using a single VRF seed to derive multiple sub-randomness values.
     *
     * @dev    Algorithm:
     *         1. Build a weighted ticket array where each participant occupies
     *            `balance` slots – this gives proportional probability without
     *            needing floating point arithmetic.
     *         2. For each of the 5 winner slots:
     *            a. Derive a unique sub-seed:  keccak256(seed, slot)
     *            b. Pick a random index in the remaining pool
     *            c. Record the winner, mark their slots as consumed
     *
     *         Gas note: for large participant sets, consider off-chain selection
     *         with on-chain verification in production.
     *
     * @param  eligible  Array of eligible participant addresses
     * @param  seed      Random seed from Chainlink VRF
     * @return winners   5-element array: index 0 = grand winner, 1-4 = small winners
     */
    function selectWinners(
        address[] memory eligible,
        uint256 seed
    ) internal pure returns (address[5] memory winners) {
        require(eligible.length >= 5, "LotteryLogic: insufficient participants");

        // Fisher-Yates partial shuffle (in-memory copy to avoid storage writes)
        address[] memory pool = _copyArray(eligible);
        uint256 remaining     = pool.length;

        for (uint256 slot = 0; slot < 5; slot++) {
            // Derive unique sub-seed for this slot
            uint256 subSeed = uint256(keccak256(abi.encodePacked(seed, slot)));

            // Pick random index in remaining pool
            uint256 idx = subSeed % remaining;

            // Record winner
            winners[slot] = pool[idx];

            // Swap picked element to the end of the active range and shrink
            pool[idx] = pool[remaining - 1];
            remaining--;
        }

        // Postcondition: all 5 winners must be unique (guaranteed by algorithm)
        _assertUnique(winners);
    }

    /**
     * @notice Weighted version of selectWinners.
     *         Participants with more tickets have proportionally higher odds.
     *
     * @dev    Builds a cumulative-weight array and binary-searches for each draw.
     *         This is O(n·log n) and suitable for up to ~500 participants.
     *
     * @param  eligible  Array of eligible participant addresses
     * @param  balances  Ticket balance for each corresponding participant
     * @param  seed      Random seed from Chainlink VRF
     * @return winners   5-element array: index 0 = grand winner, 1-4 = small winners
     */
    function selectWeightedWinners(
        address[] memory eligible,
        uint256[] memory balances,
        uint256 seed
    ) internal pure returns (address[5] memory winners) {
        require(eligible.length >= 5,              "LotteryLogic: insufficient participants");
        require(eligible.length == balances.length, "LotteryLogic: length mismatch");

        // Build cumulative weights
        uint256[] memory cumulative = new uint256[](eligible.length);
        uint256 totalWeight = 0;
        for (uint256 i = 0; i < eligible.length; i++) {
            totalWeight  += balances[i];
            cumulative[i] = totalWeight;
        }
        require(totalWeight > 0, "LotteryLogic: zero total weight");

        // Track selected indices to enforce uniqueness
        bool[] memory selected = new bool[](eligible.length);
        uint256 winnersFound   = 0;

        for (uint256 attempt = 0; winnersFound < 5; attempt++) {
            require(attempt < eligible.length * 10, "LotteryLogic: too many attempts");

            // Derive sub-seed
            uint256 subSeed  = uint256(keccak256(abi.encodePacked(seed, attempt)));
            uint256 target   = (subSeed % totalWeight) + 1; // 1-indexed

            // Binary search in cumulative weights
            uint256 lo  = 0;
            uint256 hi  = cumulative.length - 1;
            while (lo < hi) {
                uint256 mid = (lo + hi) / 2;
                if (cumulative[mid] < target) lo = mid + 1;
                else                           hi = mid;
            }

            // lo is the selected participant index
            if (!selected[lo]) {
                selected[lo]       = true;
                winners[winnersFound] = eligible[lo];
                winnersFound++;
            }
        }

        _assertUnique(winners);
    }

    // ─────────────────────────────────────────────
    //  Helpers
    // ─────────────────────────────────────────────

    /// @dev Shallow copy of an address array into memory
    function _copyArray(address[] memory src) private pure returns (address[] memory dst) {
        dst = new address[](src.length);
        for (uint256 i = 0; i < src.length; i++) {
            dst[i] = src[i];
        }
    }

    /// @dev Revert if any two winners share the same address
    function _assertUnique(address[5] memory winners) private pure {
        for (uint256 i = 0; i < 5; i++) {
            require(winners[i] != address(0), "LotteryLogic: zero winner address");
            for (uint256 j = i + 1; j < 5; j++) {
                require(winners[i] != winners[j], "LotteryLogic: duplicate winner");
            }
        }
    }

    // ─────────────────────────────────────────────
    //  Utilities (can be called externally for testing)
    // ─────────────────────────────────────────────

    /**
     * @notice Derives a slot-specific seed from a master VRF seed.
     * @param  masterSeed The raw VRF random word
     * @param  slot       Winner slot index (0 = grand, 1-4 = small)
     */
    function deriveSubSeed(uint256 masterSeed, uint256 slot)
        internal
        pure
        returns (uint256)
    {
        return uint256(keccak256(abi.encodePacked(masterSeed, slot)));
    }

    /**
     * @notice Validates that an address is not the zero address and not already
     *         present in a partial winners list.
     */
    function isValidNewWinner(
        address candidate,
        address[5] memory existing,
        uint256 count
    ) internal pure returns (bool) {
        if (candidate == address(0)) return false;
        for (uint256 i = 0; i < count; i++) {
            if (existing[i] == candidate) return false;
        }
        return true;
    }
}
