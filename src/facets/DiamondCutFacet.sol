// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IDiamond} from "../interfaces/IDiamond.sol";
import {IErrors} from "../interfaces/IErrors.sol";
import {IEvents} from "../interfaces/IEvents.sol";
import {Roles} from "../interfaces/Roles.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";
import {Layout} from "../storage/Layout.sol";

/// @title The only way the function table changes
/// @notice Runs by `delegatecall`, so it reads the token's storage. It cannot
///         touch the ERC-20 core: `LibDiamond` refuses, and this facet has no
///         way to ask it not to.
contract DiamondCutFacet is IErrors {
    /// @notice Add, replace or remove selectors
    /// @dev Where the issuer configured a delay, the first call **schedules**
    ///      and returns without changing anything; the second, after the delay,
    ///      executes. Callers must not assume one call is enough — check
    ///      `scheduledAt`.
    function diamondCut(IDiamond.FacetCut[] calldata cuts, address init, bytes calldata data) external {
        _onlyUpgradeAdmin();

        bytes32 cutHash = keccak256(abi.encode(cuts, init, data));
        if (!LibDiamond.scheduleOrCheck(cutHash)) return;

        LibDiamond.cut(cuts);

        if (init != address(0)) {
            (bool ok, bytes memory result) = init.delegatecall(data);
            if (!ok) {
                // The initialiser reverted without data; name its selector if the
                // calldata is long enough to carry one.
                if (result.length == 0) {
                    revert FunctionNotFound(data.length >= 4 ? bytes4(data[:4]) : bytes4(0));
                }
                assembly {
                    revert(add(result, 0x20), mload(result))
                }
            }
        }
    }

    /// @notice Abandon a scheduled cut
    function cancelCut(bytes32 cutHash) external {
        _onlyUpgradeAdmin();
        Layout.UpgradeStorage storage u = Layout.upgrade();
        if (u.scheduledAt[cutHash] == 0) revert UpgradeNotScheduled(cutHash);
        u.scheduledAt[cutHash] = 0;
        emit IEvents.UpgradeCancelled(cutHash);
    }

    /// @notice Change the delay
    /// @dev **Raising is immediate; lowering waits out the current delay.**
    ///      Otherwise the guarantee is worthless: an admin would set the delay
    ///      to zero and cut in the same transaction, and a holder who relied on
    ///      having a week's notice would have had none.
    ///
    ///      A pending reduction is scheduled like any other change and is
    ///      publicly visible for exactly the period it is shortening.
    function setUpgradeDelay(uint64 newDelay) external {
        _onlyUpgradeAdmin();
        Layout.UpgradeStorage storage u = Layout.upgrade();

        if (newDelay >= u.delay) {
            u.delay = newDelay;
            emit IEvents.UpgradeDelaySet(newDelay);
            return;
        }

        bytes32 key = keccak256(abi.encode("setUpgradeDelay", newDelay));
        if (!LibDiamond.scheduleOrCheck(key)) return;
        u.delay = newDelay;
        emit IEvents.UpgradeDelaySet(newDelay);
    }

    function upgradeDelay() external view returns (uint64) {
        return Layout.upgrade().delay;
    }

    function scheduledAt(bytes32 cutHash) external view returns (uint64) {
        return Layout.upgrade().scheduledAt[cutHash];
    }

    function _onlyUpgradeAdmin() private view {
        if (!Layout.roles().roles[Roles.UPGRADE_ADMIN][msg.sender]) {
            revert NotAuthorized(msg.sender, Roles.UPGRADE_ADMIN);
        }
    }
}
