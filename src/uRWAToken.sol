// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IDiamond} from "./interfaces/IDiamond.sol";
import {IErrors} from "./interfaces/IErrors.sol";
import {IEvents} from "./interfaces/IEvents.sol";
import {IuRWAToken} from "./interfaces/IuRWAToken.sol";
import {DiamondCutFacet} from "./facets/DiamondCutFacet.sol";
import {LibDiamond} from "./libraries/LibDiamond.sol";
import {Roles} from "./interfaces/Roles.sol";
import {Layout} from "./storage/Layout.sol";

/// @title uRWAToken — the ledger plane
/// @notice An ERC-20 whose accounting lives in the diamond itself and whose
///         compliance lives in replaceable facets. The split is not a
///         convention: the ERC-20 selectors are registered against this
///         contract at construction, and `LibDiamond` refuses every cut that
///         would touch them.
/// @dev What that buys, precisely: a bug anywhere in the compliance system can
///      stop transfers, and cannot rewrite a balance. An upgrade admin whose
///      key is stolen can install any facet they like and still cannot reach
///      `balances`.
///
///      Transfers call out to the compliance facet through the fallback, so a
///      token with no compliance facet installed reverts `FunctionNotFound` on
///      every transfer — it fails closed, without any code saying so.
contract uRWAToken is IuRWAToken, IEvents, IErrors {
    /// @dev The selectors that can never be cut. Registered here, once.
    function _immutableSelectors() private pure returns (bytes4[] memory sel) {
        sel = new bytes4[](14);
        sel[0] = IuRWAToken.name.selector;
        sel[1] = IuRWAToken.symbol.selector;
        sel[2] = IuRWAToken.decimals.selector;
        sel[3] = IuRWAToken.totalSupply.selector;
        sel[4] = IuRWAToken.balanceOf.selector;
        sel[5] = IuRWAToken.allowance.selector;
        sel[6] = IuRWAToken.transfer.selector;
        sel[7] = IuRWAToken.transferFrom.selector;
        sel[8] = IuRWAToken.approve.selector;
        sel[9] = IuRWAToken.nonces.selector;
        sel[10] = IuRWAToken.maxSupply.selector;
        sel[11] = IuRWAToken.owner.selector;
        sel[12] = IuRWAToken.permit.selector;
        sel[13] = IuRWAToken.DOMAIN_SEPARATOR.selector;
    }

    /// @dev The loupe. Immutable for the same reason the ledger is: an outsider
    ///      proving what a token runs must not depend on the issuer having left
    ///      the means to prove it installed.
    function _loupeSelectors() private pure returns (bytes4[] memory sel) {
        sel = new bytes4[](5);
        sel[0] = IDiamond.facets.selector;
        sel[1] = IDiamond.facetAddresses.selector;
        sel[2] = IDiamond.facetAddress.selector;
        sel[3] = IDiamond.facetFunctionSelectors.selector;
        sel[4] = IDiamond.supportsInterface.selector;
    }

    /// @param cutFacet The upgrade machinery, registered here because a diamond
    ///        cannot install its own installer through a cut.
    /// @param bootstrapAdmin_ Granted both `UPGRADE_ADMIN` and `ISSUER_ADMIN`,
    ///        because a token with no administrator cannot be configured and a
    ///        diamond cannot grant its first role through a cut. The factory
    ///        passes itself here and gives both up before the call returns.
    /// @param upgradeDelay_ Seconds a cut waits before it may execute; `0` for
    ///        none. Public through the loupe, because a token with a delay and
    ///        one without are different instruments.
    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint256 maxSupply_,
        address owner_,
        address cutFacet,
        address bootstrapAdmin_,
        uint64 upgradeDelay_
    ) {
        Layout.CoreStorage storage c = Layout.core();
        c.name = name_;
        c.symbol = symbol_;
        c.decimals = decimals_;
        c.maxSupply = maxSupply_;

        LibDiamond.registerImmutable(_immutableSelectors());
        // The loupe is registered against the diamond too, and for the same
        // reason as the ledger: a loupe an admin can cut out proves nothing on
        // the day somebody needs it to.
        LibDiamond.registerImmutable(_loupeSelectors());

        // The installer cannot be installed by a cut, so it is registered
        // directly — as a facet, not against the diamond, so it stays
        // replaceable like every other piece of the policy plane.
        LibDiamond.DiamondStorage storage d = LibDiamond.s();
        d.facetOf[DiamondCutFacet.diamondCut.selector] = cutFacet;
        d.facetOf[DiamondCutFacet.cancelCut.selector] = cutFacet;
        d.facetOf[DiamondCutFacet.upgradeDelay.selector] = cutFacet;
        d.facetOf[DiamondCutFacet.scheduledAt.selector] = cutFacet;
        d.facetOf[DiamondCutFacet.setUpgradeDelay.selector] = cutFacet;
        d.selectorsOf[cutFacet].push(DiamondCutFacet.diamondCut.selector);
        d.selectorsOf[cutFacet].push(DiamondCutFacet.cancelCut.selector);
        d.selectorsOf[cutFacet].push(DiamondCutFacet.upgradeDelay.selector);
        d.selectorsOf[cutFacet].push(DiamondCutFacet.scheduledAt.selector);
        d.selectorsOf[cutFacet].push(DiamondCutFacet.setUpgradeDelay.selector);
        d.facetAddresses.push(cutFacet);

        Layout.upgrade().delay = upgradeDelay_;
        Layout.RolesStorage storage roles = Layout.roles();
        roles.roles[Roles.UPGRADE_ADMIN][bootstrapAdmin_] = true;
        roles.members[Roles.UPGRADE_ADMIN].push(bootstrapAdmin_);
        roles.roles[Roles.ISSUER_ADMIN][bootstrapAdmin_] = true;
        roles.members[Roles.ISSUER_ADMIN].push(bootstrapAdmin_);
        emit RoleGranted(Roles.UPGRADE_ADMIN, bootstrapAdmin_, msg.sender);
        emit RoleGranted(Roles.ISSUER_ADMIN, bootstrapAdmin_, msg.sender);

        _owner = owner_;
        _domainAtDeploy = _buildDomain(name_);
    }

    function _buildDomain(string memory name_) private view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name_)),
                keccak256("1"),
                block.chainid,
                address(this)
            )
        );
    }

    address private _owner;
    address private immutable _deployer = msg.sender;
    uint256 private immutable _chainIdAtDeploy = block.chainid;
    bytes32 private immutable _domainAtDeploy;

    bytes32 private constant _PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    function deployer() external view returns (address) {
        return _deployer;
    }

    // ── ERC-20, immutable ───────────────────────────────────────────────────

    function name() external view returns (string memory) {
        return Layout.core().name;
    }

    function symbol() external view returns (string memory) {
        return Layout.core().symbol;
    }

    function decimals() external view returns (uint8) {
        return Layout.core().decimals;
    }

    function totalSupply() external view returns (uint256) {
        return Layout.core().totalSupply;
    }

    function maxSupply() external view returns (uint256) {
        return Layout.core().maxSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return Layout.core().balances[account];
    }

    function allowance(address holder, address spender) external view returns (uint256) {
        return Layout.core().allowances[holder][spender];
    }

    function nonces(address holder) external view returns (uint256) {
        return Layout.core().nonces[holder];
    }

    function owner() external view returns (address) {
        return _owner;
    }

    function approve(address spender, uint256 value) external returns (bool) {
        if (spender == address(0)) revert ERC20InvalidSpender(spender);
        Layout.core().allowances[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _update(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        _spendAllowance(from, msg.sender, value);
        _update(from, to, value);
        return true;
    }

    /// @notice EIP-712 domain
    /// @dev Rebuilt when the chain id differs from deployment, so a signature
    ///      cannot be replayed onto a fork of this chain.
    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return block.chainid == _chainIdAtDeploy ? _domainAtDeploy : _buildDomain(Layout.core().name);
    }

    /// @notice Approve by signature instead of a transaction
    /// @dev Approval is deliberately **not** compliance-checked, here or in
    ///      `approve`. Anyone may hold an allowance; the check happens when
    ///      tokens actually move. Gating approvals would break ordinary DeFi
    ///      patterns without adding safety.
    function permit(address holder, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 sig)
        external
    {
        if (block.timestamp > deadline) revert InstructionExpired(uint64(deadline));
        if (spender == address(0)) revert ERC20InvalidSpender(spender);

        Layout.CoreStorage storage c = Layout.core();
        bytes32 structHash =
            keccak256(abi.encode(_PERMIT_TYPEHASH, holder, spender, value, c.nonces[holder]++, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), structHash));

        address signer = ecrecover(digest, v, r, sig);
        if (signer == address(0) || signer != holder) revert BadSignature(holder);

        c.allowances[holder][spender] = value;
        emit Approval(holder, spender, value);
    }

    // ── the hook ────────────────────────────────────────────────────────────

    /// @notice Every movement of value passes through here
    /// @dev The compliance check is a call **out** to whatever facet currently
    ///      serves `beforeUpdate`. If none does, the call reverts and no
    ///      transfer happens. That is the fail-closed property, and it comes
    ///      from the router rather than from a flag anyone can set.
    function _update(address from, address to, uint256 value) private {
        if (to == address(0)) revert ERC20InvalidReceiver(to);

        (bool ok, bytes memory data) =
            address(this).call(abi.encodeWithSignature("beforeUpdate(address,address,uint256)", from, to, value));
        if (!ok) _bubble(data);

        Layout.CoreStorage storage c = Layout.core();
        uint256 balance = c.balances[from];
        if (balance < value) revert ERC20InsufficientBalance(from, balance, value);
        unchecked {
            c.balances[from] = balance - value;
            c.balances[to] += value;
        }
        // Holder accounting runs after the move, through the same router. It
        // cannot refuse a transfer the pipeline already allowed; if no facet
        // serves it, the token simply does not maintain subject counts.
        (bool counted,) =
            address(this).call(abi.encodeWithSignature("afterUpdate(address,address,uint256)", from, to, value));
        counted;

        emit Transfer(from, to, value);
    }

    function _spendAllowance(address from, address spender, uint256 value) private {
        Layout.CoreStorage storage c = Layout.core();
        uint256 current = c.allowances[from][spender];
        if (current != type(uint256).max) {
            if (current < value) revert ERC20InsufficientAllowance(spender, current, value);
            unchecked {
                c.allowances[from][spender] = current - value;
            }
        }
    }

    /// @dev Re-raises the callee's revert data unchanged, so a holder sees the
    ///      rule that refused rather than a generic failure.
    function _bubble(bytes memory data) private pure {
        if (data.length == 0) revert ERC7943CannotTransfer(address(0), address(0), 0);
        assembly {
            revert(add(data, 0x20), mload(data))
        }
    }

    // ── loupe, minimal ──────────────────────────────────────────────────────

    function facetAddress(bytes4 selector) external view returns (address) {
        return LibDiamond.s().facetOf[selector];
    }

    function facets() external view returns (IDiamond.Facet[] memory out) {
        address[] storage addrs = LibDiamond.s().facetAddresses;
        out = new IDiamond.Facet[](addrs.length);
        for (uint256 i = 0; i < addrs.length; i++) {
            out[i] = IDiamond.Facet(addrs[i], LibDiamond.s().selectorsOf[addrs[i]]);
        }
    }

    function facetAddresses() external view returns (address[] memory) {
        return LibDiamond.s().facetAddresses;
    }

    /// @notice The selectors one facet serves
    /// @dev Empty for an address that is not installed. Passing the token's own
    ///      address returns the immutable set — the ledger and the loupe — which
    ///      is how an outsider enumerates what no cut can reach.
    function facetFunctionSelectors(address facet) external view returns (bytes4[] memory) {
        return LibDiamond.s().selectorsOf[facet];
    }

    function supportsInterface(bytes4 interfaceId) external view returns (bool) {
        return interfaceId == 0x01ffc9a7 // ERC-165
            || interfaceId == 0x36372b07 // ERC-20
            || interfaceId == 0x3edbb4c4 // ERC-7943
            || LibDiamond.s().supportedInterface[interfaceId];
    }

    // ── the router ──────────────────────────────────────────────────────────

    /// @dev An unknown selector reverts rather than silently succeeding. A
    ///      diamond that returns empty data for an unrecognised call is a
    ///      diamond where removing the compliance facet makes every transfer
    ///      appear to work.
    fallback() external payable {
        address facet = LibDiamond.s().facetOf[msg.sig];
        if (facet == address(0)) revert FunctionNotFound(msg.sig);

        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), facet, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    receive() external payable {}
}
