// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IErrors} from "../interfaces/IErrors.sol";
import {IEvents} from "../interfaces/IEvents.sol";
import {Roles} from "../interfaces/Roles.sol";
import {Layout} from "../storage/Layout.sol";

/// @title Who is allowed to do what
/// @notice Four roles on the token, each unable to do another's work. The
///         separation matters most in the failure case: a compromised upgrade
///         admin can stop the token and cannot move a balance — not by policy,
///         but because the ERC-20 selectors are not replaceable.
/// @dev Every role is administered by `ISSUER_ADMIN`, including `ISSUER_ADMIN`
///      itself. A role that administers itself can be lost by mistake, so
///      `renounceRole` refuses when it would leave a role empty.
contract RolesFacet is IErrors {
    function grantRole(bytes32 role, address account) external {
        _onlyAdmin();
        if (account == address(0)) revert ZeroAddress();
        Layout.RolesStorage storage s = Layout.roles();
        if (s.roles[role][account]) return;

        s.roles[role][account] = true;
        s.members[role].push(account);
        emit IEvents.RoleGranted(role, account, msg.sender);
    }

    function revokeRole(bytes32 role, address account) external {
        _onlyAdmin();
        _remove(role, account);
    }

    /// @notice Give up a role you hold
    /// @dev Refuses if it would empty the role. A token whose only compliance
    ///      officer renounces is a token that can never be paused again, and
    ///      the mistake is unrecoverable.
    function renounceRole(bytes32 role) external {
        _remove(role, msg.sender);
    }

    function hasRole(bytes32 role, address account) external view returns (bool) {
        return Layout.roles().roles[role][account];
    }

    function roleAdmin(bytes32) external pure returns (bytes32) {
        return Roles.ISSUER_ADMIN;
    }

    function getRoleMemberCount(bytes32 role) external view returns (uint256 count) {
        address[] storage members = Layout.roles().members[role];
        for (uint256 i = 0; i < members.length; i++) {
            if (Layout.roles().roles[role][members[i]]) count++;
        }
    }

    function getRoleMember(bytes32 role, uint256 index) external view returns (address) {
        address[] storage members = Layout.roles().members[role];
        uint256 seen;
        for (uint256 i = 0; i < members.length; i++) {
            if (Layout.roles().roles[role][members[i]]) {
                if (seen == index) return members[i];
                seen++;
            }
        }
        return address(0);
    }

    function _remove(bytes32 role, address account) private {
        Layout.RolesStorage storage s = Layout.roles();
        if (!s.roles[role][account]) return;

        uint256 remaining;
        address[] storage members = s.members[role];
        for (uint256 i = 0; i < members.length; i++) {
            if (members[i] != account && s.roles[role][members[i]]) remaining++;
        }
        if (remaining == 0) revert NotAuthorized(account, role);

        s.roles[role][account] = false;
        emit IEvents.RoleRevoked(role, account, msg.sender);
    }

    function _onlyAdmin() private view {
        if (!Layout.roles().roles[Roles.ISSUER_ADMIN][msg.sender]) {
            revert NotAuthorized(msg.sender, Roles.ISSUER_ADMIN);
        }
    }
}

/// @title ERC-1404 compatibility
/// @notice For integrators that predate ERC-7943 and read a numeric code.
/// @dev A translation of `whyBlocked`, never a second opinion: both call the
///      same evaluation, so an integrator on the older interface gets the same
///      answer as one on the newer.
contract Erc1404Facet {
    function detectTransferRestriction(address from, address to, uint256 amount) external view returns (uint8) {
        (bool ok, bytes memory data) =
            address(this).staticcall(abi.encodeWithSignature("whyBlocked(address,address,uint256)", from, to, amount));
        if (!ok) return 255;
        (uint8 stage,,) = abi.decode(data, (uint8, address, string));
        return stage;
    }

    function messageForTransferRestriction(uint8 code) external pure returns (string memory) {
        if (code == 0) return "transfer permitted";
        if (code == 1) return "all transfers are paused";
        if (code == 2) return "one party is paused";
        if (code == 3) return "the sender may not send";
        if (code == 4) return "the recipient may not receive";
        if (code == 5) return "amount exceeds the unfrozen balance";
        if (code == 6) return "a compliance rule refused";
        return "unknown restriction";
    }
}
