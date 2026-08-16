// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {uRWAFactory} from "../src/uRWAFactory.sol";
import {Treasury} from "../src/Treasury.sol";
import {OfferingRegistry} from "../src/OfferingRegistry.sol";
import {ComplianceFacet} from "../src/facets/ComplianceFacet.sol";
import {DiamondCutFacet} from "../src/facets/DiamondCutFacet.sol";
import {MonetaryFacet} from "../src/facets/MonetaryFacet.sol";
import {PurchaseFacet} from "../src/facets/PurchaseFacet.sol";
import {FreezeFacet, LockupFacet} from "../src/facets/RestrictionFacets.sol";
import {Erc1404Facet, RolesFacet} from "../src/facets/RolesFacet.sol";
import {AllowlistRegistry} from "../src/identity/Adapters.sol";
import {HasValidIdentity, JurisdictionRule, MaxHolders, RequiresClaim} from "../src/rules/RuleLibrary.sol";
import {IDiamond} from "../src/interfaces/IDiamond.sol";
import {ClaimKeys} from "../src/interfaces/Roles.sol";
import {TokenParams} from "../src/interfaces/IuRWAFactory.sol";

/// @title The stack, stood up — doc 16 steps 2 to 7, in code
/// @notice Everything a chain needs once: facet implementations, the factory,
///         the offering registry, the tier-0 identity registry, the shared rule
///         contracts, and the packages and presets registered. After this, a
///         token is one `createToken` call.
/// @dev The logic lives here rather than in the scripts' `run()` so the test
///      suite deploys through **exactly this code** — the script CI proves is
///      the script an operator runs. MiCA presets are deliberately absent:
///      `MiCARule` is parameterised by the issuer's subject, so a MiCA regime
///      is composed per issuance, not registered chain-wide.
abstract contract StackDeployer {
    // ── what gets deployed ──────────────────────────────────────────────────

    DiamondCutFacet public cutFacet;
    Treasury public treasuryImplementation;
    uRWAFactory public factory;
    OfferingRegistry public offeringRegistry;
    AllowlistRegistry public identityRegistry;

    ComplianceFacet public complianceFacet;
    MonetaryFacet public monetaryFacet;
    RolesFacet public rolesFacet;
    FreezeFacet public freezeFacet;
    LockupFacet public lockupFacet;
    Erc1404Facet public erc1404Facet;
    PurchaseFacet public purchaseFacet;

    HasValidIdentity public identityRule;
    RequiresClaim public accreditedRule;
    RequiresClaim public sanctionsRule;
    JurisdictionRule public jurisdictionDenyUS;
    MaxHolders public maxHolders;

    // ── the names an operator refers to ─────────────────────────────────────

    bytes32 public constant PACKAGE_BASE = keccak256("base.v1");
    bytes32 public constant PACKAGE_BASE_PURCHASE = keccak256("base+purchase.v1");
    bytes32 public constant PRESET_REGD = keccak256("RegD506c");
    bytes32 public constant PRESET_REGS = keccak256("RegS");
    bytes32 public constant PRESET_OPEN = keccak256("Open");

    /// @dev Sanctions screening freshness. Zero — no staleness window — until
    ///      the per-datapoint windows are settled at `PA-03`; the claim's own
    ///      validity and revocation still apply through the adapter.
    uint64 internal constant SANCTIONS_FRESHNESS = 0;

    /// @notice Stand the chain's shared infrastructure up
    /// @param admin Owns the offering registry and the tier-0 allowlist. The
    ///        factory's admin is whoever runs this — its packages and presets
    ///        are registered in the same run.
    function _deployStack(address admin) internal {
        // 1 · the pieces every token shares
        cutFacet = new DiamondCutFacet();
        treasuryImplementation = new Treasury();
        factory = new uRWAFactory(address(cutFacet), address(treasuryImplementation));
        offeringRegistry = new OfferingRegistry(admin);
        identityRegistry = new AllowlistRegistry(admin);

        // 2 · facet implementations, deployed once and referenced by every token
        complianceFacet = new ComplianceFacet();
        monetaryFacet = new MonetaryFacet();
        rolesFacet = new RolesFacet();
        freezeFacet = new FreezeFacet();
        lockupFacet = new LockupFacet();
        erc1404Facet = new Erc1404Facet();
        purchaseFacet = new PurchaseFacet();

        // 3 · packages: the base feature set, and base plus the offering door.
        //     No emergency package — installing seizure is a deliberate act an
        //     issuer performs by cut, never a default anyone can pick blind.
        factory.registerPackage(PACKAGE_BASE, _basePackage());
        factory.registerPackage(PACKAGE_BASE_PURCHASE, _basePurchasePackage());

        // 4 · the shared rules — stateless, one deployment serving every token
        identityRule = new HasValidIdentity(address(identityRegistry));
        accreditedRule = new RequiresClaim(address(identityRegistry), ClaimKeys.US_ACCREDITED, "not accredited", 0, 0);
        sanctionsRule = new RequiresClaim(
            address(identityRegistry), ClaimKeys.AML_SANCTIONS_CLEAR, "sanctions not cleared", 0, SANCTIONS_FRESHNESS
        );
        bytes32[] memory us = new bytes32[](1);
        us[0] = keccak256("US"); // countries travel as hashes; see doc 10
        jurisdictionDenyUS = new JurisdictionRule(address(identityRegistry), true, us);
        maxHolders = new MaxHolders(2000); // the Reg D holder-register bound

        // 5 · the presets — parallel arrays, rules[i] in groups[i]; every group
        //     here is distinct, so each regime is a pure AND
        _registerPreset(PRESET_REGD, _regD());
        _registerPreset(PRESET_REGS, _regS());
        _registerPreset(PRESET_OPEN, _open());
    }

    // ── preset compositions, from doc 10 ────────────────────────────────────

    function _regD() private view returns (address[] memory rules) {
        rules = new address[](4);
        rules[0] = address(identityRule);
        rules[1] = address(accreditedRule);
        rules[2] = address(sanctionsRule);
        rules[3] = address(maxHolders);
    }

    function _regS() private view returns (address[] memory rules) {
        rules = new address[](3);
        rules[0] = address(identityRule);
        rules[1] = address(jurisdictionDenyUS);
        rules[2] = address(sanctionsRule);
    }

    function _open() private view returns (address[] memory rules) {
        rules = new address[](2);
        rules[0] = address(identityRule);
        rules[1] = address(sanctionsRule);
    }

    function _registerPreset(bytes32 id, address[] memory rules) private {
        bytes32[] memory groups = new bytes32[](rules.length);
        for (uint256 i = 0; i < rules.length; i++) {
            // Each rule its own group: distinct groups AND together.
            groups[i] = bytes32(uint256(i + 1));
        }
        factory.registerPreset(id, rules, groups);
    }

    // ── packages: every selector each facet serves ──────────────────────────

    function _basePackage() internal view returns (IDiamond.FacetCut[] memory cuts) {
        cuts = new IDiamond.FacetCut[](5);
        cuts[0] = IDiamond.FacetCut(address(complianceFacet), IDiamond.FacetCutAction.Add, _complianceSelectors());
        cuts[1] = IDiamond.FacetCut(address(monetaryFacet), IDiamond.FacetCutAction.Add, _monetarySelectors());
        cuts[2] = IDiamond.FacetCut(address(rolesFacet), IDiamond.FacetCutAction.Add, _rolesSelectors());
        cuts[3] = IDiamond.FacetCut(address(freezeFacet), IDiamond.FacetCutAction.Add, _freezeSelectors());
        cuts[4] = IDiamond.FacetCut(address(lockupFacet), IDiamond.FacetCutAction.Add, _lockupSelectors());
    }

    function _basePurchasePackage() internal view returns (IDiamond.FacetCut[] memory cuts) {
        IDiamond.FacetCut[] memory base = _basePackage();
        cuts = new IDiamond.FacetCut[](base.length + 2);
        for (uint256 i = 0; i < base.length; i++) {
            cuts[i] = base[i];
        }
        cuts[base.length] = IDiamond.FacetCut(address(erc1404Facet), IDiamond.FacetCutAction.Add, _erc1404Selectors());
        cuts[base.length + 1] =
            IDiamond.FacetCut(address(purchaseFacet), IDiamond.FacetCutAction.Add, _purchaseSelectors());
    }

    function _complianceSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](27);
        s[0] = ComplianceFacet.beforeUpdate.selector;
        s[1] = ComplianceFacet.afterUpdate.selector;
        s[2] = ComplianceFacet.subjectOf.selector;
        s[3] = ComplianceFacet.canSend.selector;
        s[4] = ComplianceFacet.canReceive.selector;
        s[5] = ComplianceFacet.canTransfer.selector;
        s[6] = ComplianceFacet.getFrozenTokens.selector;
        s[7] = ComplianceFacet.unfrozenBalanceOf.selector;
        s[8] = ComplianceFacet.whyBlocked.selector;
        s[9] = ComplianceFacet.policySet.selector;
        s[10] = ComplianceFacet.identityRegistry.selector;
        s[11] = ComplianceFacet.setPolicySet.selector;
        s[12] = ComplianceFacet.setIdentityRegistry.selector;
        s[13] = ComplianceFacet.trust.selector;
        s[14] = ComplianceFacet.distrust.selector;
        s[15] = ComplianceFacet.isTrusted.selector;
        s[16] = ComplianceFacet.trustList.selector;
        s[17] = ComplianceFacet.trustReasonOf.selector;
        s[18] = ComplianceFacet.pause.selector;
        s[19] = ComplianceFacet.unpause.selector;
        s[20] = ComplianceFacet.paused.selector;
        s[21] = ComplianceFacet.pauseAddress.selector;
        s[22] = ComplianceFacet.unpauseAddress.selector;
        s[23] = ComplianceFacet.addressPaused.selector;
        s[24] = ComplianceFacet.holderCount.selector;
        s[25] = ComplianceFacet.subjectHolderCount.selector;
        s[26] = ComplianceFacet.subjectBalanceOf.selector;
    }

    function _monetarySelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](11);
        s[0] = MonetaryFacet.issue.selector;
        s[1] = MonetaryFacet.redeem.selector;
        s[2] = MonetaryFacet.distributeFromTreasury.selector;
        s[3] = MonetaryFacet.setMaxSupply.selector;
        s[4] = MonetaryFacet.lockCap.selector;
        s[5] = MonetaryFacet.capLocked.selector;
        s[6] = MonetaryFacet.totalIssued.selector;
        s[7] = MonetaryFacet.treasury.selector;
        s[8] = MonetaryFacet.setTreasury.selector;
        s[9] = MonetaryFacet.offeringRegistry.selector;
        s[10] = MonetaryFacet.setOfferingRegistry.selector;
    }

    function _rolesSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](7);
        s[0] = RolesFacet.grantRole.selector;
        s[1] = RolesFacet.revokeRole.selector;
        s[2] = RolesFacet.renounceRole.selector;
        s[3] = RolesFacet.hasRole.selector;
        s[4] = RolesFacet.roleAdmin.selector;
        s[5] = RolesFacet.getRoleMemberCount.selector;
        s[6] = RolesFacet.getRoleMember.selector;
    }

    function _freezeSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](2);
        s[0] = FreezeFacet.setFrozenTokens.selector;
        s[1] = FreezeFacet.adminFrozenOf.selector;
    }

    function _lockupSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](6);
        s[0] = LockupFacet.addLockup.selector;
        s[1] = LockupFacet.clearLockups.selector;
        s[2] = LockupFacet.releaseExpired.selector;
        s[3] = LockupFacet.lockupsOf.selector;
        s[4] = LockupFacet.lockupCount.selector;
        s[5] = LockupFacet.lockedAmountOf.selector;
    }

    function _erc1404Selectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](2);
        s[0] = Erc1404Facet.detectTransferRestriction.selector;
        s[1] = Erc1404Facet.messageForTransferRestriction.selector;
    }

    function _purchaseSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](3);
        s[0] = PurchaseFacet.purchase.selector;
        s[1] = PurchaseFacet.previewPurchase.selector;
        s[2] = PurchaseFacet.refundPurchase.selector;
    }
}

/// @notice `forge script script/Deploy.s.sol:DeployStack --rpc-url <chain> --broadcast`
/// @dev `ADMIN` (optional) owns the offering registry and the allowlist; it
///      defaults to the broadcaster. The factory's admin is always the
///      broadcaster — registered packages and presets land in the same run.
contract DeployStack is Script, StackDeployer {
    function run() external {
        address admin = vm.envOr("ADMIN", msg.sender);
        vm.startBroadcast();
        _deployStack(admin);
        vm.stopBroadcast();

        console2.log("factory              ", address(factory));
        console2.log("offering registry    ", address(offeringRegistry));
        console2.log("identity registry    ", address(identityRegistry));
        console2.log("treasury impl        ", address(treasuryImplementation));
        console2.log("cut facet            ", address(cutFacet));
        console2.log("packages: base.v1, base+purchase.v1");
        console2.log("presets:  RegD506c, RegS, Open");
    }
}

/// @notice One token from the stack above, end to end — doc 16 steps 9 to 11
/// @dev Required: `FACTORY`, `IDENTITY_REGISTRY`. Optional: `OFFERING_REGISTRY`
///      (zero disables the purchase door), `TOKEN_NAME`, `TOKEN_SYMBOL`,
///      `MAX_SUPPLY`, `UPGRADE_DELAY` (no default is offered by the console
///      deliberately — here it defaults to zero and prints what it chose), and
///      the four role holders, each defaulting to the broadcaster.
contract DeployDemoToken is Script, StackDeployer {
    function run() external {
        uRWAFactory f = uRWAFactory(vm.envAddress("FACTORY"));
        address broadcaster = msg.sender;

        TokenParams memory p = TokenParams({
            name: vm.envOr("TOKEN_NAME", string("Demo Asset")),
            symbol: vm.envOr("TOKEN_SYMBOL", string("DEMO")),
            decimals: 18,
            maxSupply: vm.envOr("MAX_SUPPLY", uint256(0)),
            lockCap: false,
            preset: PRESET_OPEN,
            identityRegistry: vm.envAddress("IDENTITY_REGISTRY"),
            upgradeDelay: uint64(vm.envOr("UPGRADE_DELAY", uint256(0))),
            installEmergencyFacet: false,
            issuerAdmin: vm.envOr("ISSUER_ADMIN", broadcaster),
            upgradeAdmin: vm.envOr("UPGRADE_ADMIN", broadcaster),
            supplyOperator: vm.envOr("SUPPLY_OPERATOR", broadcaster),
            complianceOfficer: vm.envOr("COMPLIANCE_OFFICER", broadcaster)
        });

        vm.startBroadcast();
        (address token, address treasury) =
            f.createToken(p, PACKAGE_BASE_PURCHASE, vm.envOr("OFFERING_REGISTRY", address(0)));
        vm.stopBroadcast();

        console2.log("token    ", token);
        console2.log("treasury ", treasury);
        console2.log("preset    Open; package base+purchase.v1");
        console2.log("upgrade delay (s)", uint256(p.upgradeDelay));
    }
}
