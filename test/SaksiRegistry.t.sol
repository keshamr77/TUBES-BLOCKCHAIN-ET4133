// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, Vm} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {SaksiRegistry} from "../src/SaksiRegistry.sol";

/// @notice Uji unit dan fuzz untuk SaksiRegistry.
contract SaksiRegistryTest is Test {
    SaksiRegistry internal reg;

    address internal admin = makeAddr("admin");
    address internal investigator = makeAddr("investigator");
    address internal custodianA = makeAddr("custodianA");
    address internal custodianB = makeAddr("custodianB");
    address internal outsider = makeAddr("outsider");

    // immutable, not constant: sha256 is a precompile call and would consume vm.prank
    bytes32 internal immutable FILE_HASH = sha256("isi berkas bukti asli");
    bytes32 internal immutable TAMPERED_HASH = sha256("isi berkas bukti yang diubah");
    // Frontend menormalisasi nomor perkara (trim + huruf besar) lalu menghitung keccak256.
    bytes32 internal constant CASE_REF = keccak256("LP/123/XI/2026");
    bytes32 internal constant META_HASH = keccak256("Citra disk laptop tersangka");

    function setUp() public {
        reg = new SaksiRegistry(admin);
        vm.startPrank(admin);
        reg.grantRole(reg.INVESTIGATOR_ROLE(), investigator);
        reg.grantRole(reg.CUSTODIAN_ROLE(), custodianA);
        reg.grantRole(reg.CUSTODIAN_ROLE(), custodianB);
        vm.stopPrank();
    }

    // --- helpers ---------------------------------------------------------

    function _register() internal returns (uint256 id) {
        vm.prank(investigator);
        id = reg.registerEvidence(CASE_REF, META_HASH, FILE_HASH);
    }

    function _registerAndInitiate() internal returns (uint256 id) {
        id = _register();
        vm.prank(investigator);
        reg.initiateTransfer(id, custodianA, "Kirim ke gudang bukti");
    }

    function _status(uint256 id) internal view returns (SaksiRegistry.Status) {
        return reg.getEvidence(id).status;
    }

    // --- constructor & admin ----------------------------------------------

    function test_Constructor_GrantsAdminOnly() public view {
        assertTrue(reg.hasRole(reg.DEFAULT_ADMIN_ROLE(), admin));
        assertFalse(reg.isPersonnel(admin));
        assertEq(reg.evidenceCount(), 0);
    }

    function test_RevertWhen_ConstructorAdminIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(SaksiRegistry.InvalidRecipient.selector, address(0)));
        new SaksiRegistry(address(0));
    }

    function test_AdminCanPauseAndUnpause() public {
        vm.prank(admin);
        reg.pause();
        assertTrue(reg.paused());
        vm.prank(admin);
        reg.unpause();
        assertFalse(reg.paused());
    }

    function test_RevertWhen_NonAdminPauses() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, investigator, reg.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(investigator);
        reg.pause();
    }

    function test_RevertWhen_NonAdminUnpauses() public {
        vm.prank(admin);
        reg.pause();
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, custodianA, reg.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(custodianA);
        reg.unpause();
    }

    // --- registerEvidence ---------------------------------------------------

    function test_Register_StoresEvidence() public {
        vm.expectEmit(true, true, true, true, address(reg));
        emit SaksiRegistry.EvidenceRegistered(1, investigator, CASE_REF, FILE_HASH, META_HASH);
        uint256 id = _register();

        assertEq(id, 1);
        assertEq(reg.evidenceCount(), 1);
        assertEq(reg.evidenceIdByHash(FILE_HASH), 1);

        SaksiRegistry.Evidence memory e = reg.getEvidence(id);
        assertEq(e.caseRef, CASE_REF);
        assertEq(e.metadataHash, META_HASH);
        assertEq(e.fileHash, FILE_HASH);
        assertEq(e.holder, investigator);
        assertEq(e.pendingRecipient, address(0));
        assertEq(uint8(e.status), uint8(SaksiRegistry.Status.Stored));
        assertEq(e.registeredAt, block.timestamp);
        assertEq(e.discrepancyCount, 0);

        SaksiRegistry.CustodyRecord[] memory h = reg.getHistory(id);
        assertEq(h.length, 1);
        assertEq(uint8(h[0].action), uint8(SaksiRegistry.Action.Registered));
        assertEq(h[0].actor, investigator);
    }

    function test_RevertWhen_RegisterByCustodian() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, custodianA, reg.INVESTIGATOR_ROLE()
            )
        );
        vm.prank(custodianA);
        reg.registerEvidence(CASE_REF, META_HASH, FILE_HASH);
    }

    function test_RevertWhen_RegisterByOutsider() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, outsider, reg.INVESTIGATOR_ROLE()
            )
        );
        vm.prank(outsider);
        reg.registerEvidence(CASE_REF, META_HASH, FILE_HASH);
    }

    function test_RevertWhen_RegisterZeroHash() public {
        vm.expectRevert(SaksiRegistry.EmptyField.selector);
        vm.prank(investigator);
        reg.registerEvidence(CASE_REF, META_HASH, bytes32(0));
    }

    function test_RevertWhen_RegisterZeroCaseRef() public {
        vm.expectRevert(SaksiRegistry.EmptyField.selector);
        vm.prank(investigator);
        reg.registerEvidence(bytes32(0), META_HASH, FILE_HASH);
    }

    function test_Register_AllowsEmptyMetadata() public {
        vm.prank(investigator);
        uint256 id = reg.registerEvidence(CASE_REF, bytes32(0), FILE_HASH);
        assertEq(reg.getEvidence(id).metadataHash, bytes32(0));
    }

    /// Data perkara tidak tersimpan sebagai teks: event hanya memuat hash,
    /// dan caseRef menjadi topic sehingga bisa difilter per perkara.
    function test_Register_EventCarriesOnlyHashes() public {
        vm.recordLogs();
        _register();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].topics.length, 4);
        assertEq(logs[0].topics[0], SaksiRegistry.EvidenceRegistered.selector);
        assertEq(logs[0].topics[3], CASE_REF);
        assertEq(logs[0].data, abi.encode(FILE_HASH, META_HASH));
    }

    function test_RevertWhen_RegisterDuplicateHash() public {
        _register();
        vm.expectRevert(abi.encodeWithSelector(SaksiRegistry.DuplicateEvidence.selector, FILE_HASH, 1));
        vm.prank(investigator);
        reg.registerEvidence(keccak256("LP/999/XI/2026"), keccak256("Salinan"), FILE_HASH);
    }

    function test_RevertWhen_RegisterWhilePaused() public {
        vm.prank(admin);
        reg.pause();
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(investigator);
        reg.registerEvidence(CASE_REF, META_HASH, FILE_HASH);
    }

    // --- initiateTransfer ---------------------------------------------------

    function test_Initiate_SetsPendingRecipient() public {
        uint256 id = _register();
        vm.expectEmit(true, true, true, true, address(reg));
        emit SaksiRegistry.TransferInitiated(id, investigator, custodianA, "Kirim ke gudang bukti");
        vm.prank(investigator);
        reg.initiateTransfer(id, custodianA, "Kirim ke gudang bukti");

        SaksiRegistry.Evidence memory e = reg.getEvidence(id);
        assertEq(e.holder, investigator);
        assertEq(e.pendingRecipient, custodianA);
        assertEq(uint8(e.status), uint8(SaksiRegistry.Status.InTransfer));
        assertEq(reg.historyLength(id), 2);
    }

    function test_RevertWhen_InitiateByNonHolder() public {
        uint256 id = _register();
        vm.expectRevert(abi.encodeWithSelector(SaksiRegistry.NotHolder.selector, id, custodianA));
        vm.prank(custodianA);
        reg.initiateTransfer(id, custodianB, "");
    }

    function test_RevertWhen_InitiateToOutsider() public {
        uint256 id = _register();
        vm.expectRevert(abi.encodeWithSelector(SaksiRegistry.InvalidRecipient.selector, outsider));
        vm.prank(investigator);
        reg.initiateTransfer(id, outsider, "");
    }

    function test_RevertWhen_InitiateToAdmin() public {
        uint256 id = _register();
        vm.expectRevert(abi.encodeWithSelector(SaksiRegistry.InvalidRecipient.selector, admin));
        vm.prank(investigator);
        reg.initiateTransfer(id, admin, "");
    }

    function test_RevertWhen_InitiateToSelf() public {
        uint256 id = _register();
        vm.expectRevert(abi.encodeWithSelector(SaksiRegistry.InvalidRecipient.selector, investigator));
        vm.prank(investigator);
        reg.initiateTransfer(id, investigator, "");
    }

    function test_RevertWhen_InitiateWhileInTransfer() public {
        uint256 id = _registerAndInitiate();
        vm.expectRevert(
            abi.encodeWithSelector(SaksiRegistry.InvalidStatus.selector, id, SaksiRegistry.Status.InTransfer)
        );
        vm.prank(investigator);
        reg.initiateTransfer(id, custodianB, "");
    }

    function test_RevertWhen_InitiateUnknownEvidence() public {
        vm.expectRevert(abi.encodeWithSelector(SaksiRegistry.EvidenceNotFound.selector, 42));
        vm.prank(investigator);
        reg.initiateTransfer(42, custodianA, "");
    }

    function test_RevertWhen_InitiateNoteTooLong() public {
        uint256 id = _register();
        vm.expectRevert(abi.encodeWithSelector(SaksiRegistry.FieldTooLong.selector, 257, 256));
        vm.prank(investigator);
        reg.initiateTransfer(id, custodianA, string(new bytes(257)));
    }

    function test_RevertWhen_HolderLostRole() public {
        uint256 id = _register();
        vm.startPrank(admin);
        reg.revokeRole(reg.INVESTIGATOR_ROLE(), investigator);
        vm.stopPrank();
        vm.expectRevert(abi.encodeWithSelector(SaksiRegistry.NotPersonnel.selector, investigator));
        vm.prank(investigator);
        reg.initiateTransfer(id, custodianA, "");
    }

    function test_RevertWhen_InitiateWhilePaused() public {
        uint256 id = _register();
        vm.prank(admin);
        reg.pause();
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(investigator);
        reg.initiateTransfer(id, custodianA, "");
    }

    // --- acceptTransfer -----------------------------------------------------

    function test_Accept_MovesCustody() public {
        uint256 id = _registerAndInitiate();
        vm.expectEmit(true, true, true, true, address(reg));
        emit SaksiRegistry.TransferAccepted(id, investigator, custodianA);
        vm.prank(custodianA);
        assertTrue(reg.acceptTransfer(id, FILE_HASH));

        SaksiRegistry.Evidence memory e = reg.getEvidence(id);
        assertEq(e.holder, custodianA);
        assertEq(e.discrepancyCount, 0);
        assertEq(e.pendingRecipient, address(0));
        assertEq(uint8(e.status), uint8(SaksiRegistry.Status.Stored));

        SaksiRegistry.CustodyRecord[] memory h = reg.getHistory(id);
        assertEq(h.length, 3);
        assertEq(uint8(h[2].action), uint8(SaksiRegistry.Action.TransferAccepted));
        assertEq(h[2].actor, custodianA);
        assertEq(h[2].counterparty, investigator);
    }

    function test_Accept_TamperedFileRecordsDiscrepancy() public {
        uint256 id = _registerAndInitiate();
        vm.expectEmit(true, true, false, true, address(reg));
        emit SaksiRegistry.DiscrepancyRecorded(id, custodianA, FILE_HASH, TAMPERED_HASH);
        vm.prank(custodianA);
        bool accepted = reg.acceptTransfer(id, TAMPERED_HASH);
        assertFalse(accepted);

        // Serah-terima batal, bukti tetap pada pengirim, tanda permanen bertambah.
        SaksiRegistry.Evidence memory e = reg.getEvidence(id);
        assertEq(e.holder, investigator);
        assertEq(e.pendingRecipient, address(0));
        assertEq(uint8(e.status), uint8(SaksiRegistry.Status.Stored));
        assertEq(e.discrepancyCount, 1);
        assertEq(e.fileHash, FILE_HASH);

        SaksiRegistry.CustodyRecord[] memory h = reg.getHistory(id);
        assertEq(h.length, 3);
        assertEq(uint8(h[2].action), uint8(SaksiRegistry.Action.DiscrepancyRecorded));
        assertEq(h[2].actor, custodianA);
        assertEq(h[2].counterparty, investigator);
        assertEq(h[2].note, vm.toString(TAMPERED_HASH));
    }

    function test_Discrepancy_SenderCanRetryAndFlagStays() public {
        uint256 id = _registerAndInitiate();
        vm.prank(custodianA);
        reg.acceptTransfer(id, TAMPERED_HASH);

        // Pengirim boleh memulai serah-terima lagi, dan berkas asli diterima.
        vm.prank(investigator);
        reg.initiateTransfer(id, custodianA, "Kirim ulang berkas asli");
        vm.prank(custodianA);
        assertTrue(reg.acceptTransfer(id, FILE_HASH));

        SaksiRegistry.Evidence memory e = reg.getEvidence(id);
        assertEq(e.holder, custodianA);
        assertEq(e.discrepancyCount, 1);
        assertEq(reg.historyLength(id), 5);
    }

    function test_Discrepancy_SenderCanSendToAnotherCustodian() public {
        uint256 id = _registerAndInitiate();
        vm.prank(custodianA);
        reg.acceptTransfer(id, TAMPERED_HASH);
        vm.prank(investigator);
        reg.initiateTransfer(id, custodianB, "");
        vm.prank(custodianB);
        reg.acceptTransfer(id, TAMPERED_HASH);
        assertEq(reg.getEvidence(id).discrepancyCount, 2);
        assertEq(reg.getEvidence(id).holder, investigator);
    }

    function test_Discrepancy_CannotAcceptAfterwardsWithoutNewTransfer() public {
        uint256 id = _registerAndInitiate();
        vm.prank(custodianA);
        reg.acceptTransfer(id, TAMPERED_HASH);
        vm.expectRevert(abi.encodeWithSelector(SaksiRegistry.InvalidStatus.selector, id, SaksiRegistry.Status.Stored));
        vm.prank(custodianA);
        reg.acceptTransfer(id, FILE_HASH);
    }

    function test_RevertWhen_NonRecipientSubmitsWrongHash() public {
        uint256 id = _registerAndInitiate();
        address[3] memory callers = [custodianB, investigator, outsider];
        for (uint256 i; i < callers.length; i++) {
            vm.expectRevert(abi.encodeWithSelector(SaksiRegistry.NotPendingRecipient.selector, id, callers[i]));
            vm.prank(callers[i]);
            reg.acceptTransfer(id, TAMPERED_HASH);
        }
        // Tidak ada yang tercatat.
        assertEq(reg.getEvidence(id).discrepancyCount, 0);
        assertEq(reg.historyLength(id), 2);
    }

    function test_RevertWhen_RecipientLostRoleBeforeWrongHash() public {
        uint256 id = _registerAndInitiate();
        vm.startPrank(admin);
        reg.revokeRole(reg.CUSTODIAN_ROLE(), custodianA);
        vm.stopPrank();
        vm.expectRevert(abi.encodeWithSelector(SaksiRegistry.NotPersonnel.selector, custodianA));
        vm.prank(custodianA);
        reg.acceptTransfer(id, TAMPERED_HASH);
        assertEq(reg.getEvidence(id).discrepancyCount, 0);
    }

    function test_RevertWhen_WrongHashWhilePaused() public {
        uint256 id = _registerAndInitiate();
        vm.prank(admin);
        reg.pause();
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(custodianA);
        reg.acceptTransfer(id, TAMPERED_HASH);
        assertEq(reg.getEvidence(id).discrepancyCount, 0);
    }

    function test_RevertWhen_AcceptByWrongCustodian() public {
        uint256 id = _registerAndInitiate();
        vm.expectRevert(abi.encodeWithSelector(SaksiRegistry.NotPendingRecipient.selector, id, custodianB));
        vm.prank(custodianB);
        reg.acceptTransfer(id, FILE_HASH);
    }

    function test_RevertWhen_AcceptWithoutTransfer() public {
        uint256 id = _register();
        vm.expectRevert(abi.encodeWithSelector(SaksiRegistry.InvalidStatus.selector, id, SaksiRegistry.Status.Stored));
        vm.prank(custodianA);
        reg.acceptTransfer(id, FILE_HASH);
    }

    function test_RevertWhen_RecipientLostRoleBeforeAccept() public {
        uint256 id = _registerAndInitiate();
        vm.startPrank(admin);
        reg.revokeRole(reg.CUSTODIAN_ROLE(), custodianA);
        vm.stopPrank();
        vm.expectRevert(abi.encodeWithSelector(SaksiRegistry.NotPersonnel.selector, custodianA));
        vm.prank(custodianA);
        reg.acceptTransfer(id, FILE_HASH);
    }

    function test_RevertWhen_AcceptWhilePaused() public {
        uint256 id = _registerAndInitiate();
        vm.prank(admin);
        reg.pause();
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(custodianA);
        reg.acceptTransfer(id, FILE_HASH);
    }

    // --- rejectTransfer -----------------------------------------------------

    function test_Reject_KeepsSenderAsHolder() public {
        uint256 id = _registerAndInitiate();
        vm.expectEmit(true, true, true, true, address(reg));
        emit SaksiRegistry.TransferRejected(id, investigator, custodianA, "Segel rusak");
        vm.prank(custodianA);
        reg.rejectTransfer(id, "Segel rusak");

        SaksiRegistry.Evidence memory e = reg.getEvidence(id);
        assertEq(e.holder, investigator);
        assertEq(e.pendingRecipient, address(0));
        assertEq(uint8(e.status), uint8(SaksiRegistry.Status.Stored));
        assertEq(reg.getHistory(id)[2].note, "Segel rusak");
    }

    function test_RevertWhen_RejectByNonRecipient() public {
        uint256 id = _registerAndInitiate();
        vm.expectRevert(abi.encodeWithSelector(SaksiRegistry.NotPendingRecipient.selector, id, investigator));
        vm.prank(investigator);
        reg.rejectTransfer(id, "");
    }

    function test_RevertWhen_RejectNoteTooLong() public {
        uint256 id = _registerAndInitiate();
        vm.expectRevert(abi.encodeWithSelector(SaksiRegistry.FieldTooLong.selector, 257, 256));
        vm.prank(custodianA);
        reg.rejectTransfer(id, string(new bytes(257)));
    }

    // --- cancelTransfer -----------------------------------------------------

    function test_Cancel_RestoresStored() public {
        uint256 id = _registerAndInitiate();
        vm.expectEmit(true, true, true, true, address(reg));
        emit SaksiRegistry.TransferCancelled(id, investigator, custodianA);
        vm.prank(investigator);
        reg.cancelTransfer(id);

        SaksiRegistry.Evidence memory e = reg.getEvidence(id);
        assertEq(e.holder, investigator);
        assertEq(e.pendingRecipient, address(0));
        assertEq(uint8(e.status), uint8(SaksiRegistry.Status.Stored));

        // pending recipient can no longer accept
        vm.expectRevert(abi.encodeWithSelector(SaksiRegistry.InvalidStatus.selector, id, SaksiRegistry.Status.Stored));
        vm.prank(custodianA);
        reg.acceptTransfer(id, FILE_HASH);
    }

    function test_RevertWhen_CancelByRecipient() public {
        uint256 id = _registerAndInitiate();
        vm.expectRevert(abi.encodeWithSelector(SaksiRegistry.NotHolder.selector, id, custodianA));
        vm.prank(custodianA);
        reg.cancelTransfer(id);
    }

    function test_RevertWhen_CancelWithoutTransfer() public {
        uint256 id = _register();
        vm.expectRevert(abi.encodeWithSelector(SaksiRegistry.InvalidStatus.selector, id, SaksiRegistry.Status.Stored));
        vm.prank(investigator);
        reg.cancelTransfer(id);
    }

    // --- closeEvidence ------------------------------------------------------

    function test_Close_IsFinal() public {
        uint256 id = _register();
        vm.expectEmit(true, true, false, true, address(reg));
        emit SaksiRegistry.EvidenceClosed(id, investigator, "Perkara inkracht");
        vm.prank(investigator);
        reg.closeEvidence(id, "Perkara inkracht");
        assertEq(uint8(_status(id)), uint8(SaksiRegistry.Status.Closed));

        bytes memory err = abi.encodeWithSelector(SaksiRegistry.InvalidStatus.selector, id, SaksiRegistry.Status.Closed);
        vm.startPrank(investigator);
        vm.expectRevert(err);
        reg.initiateTransfer(id, custodianA, "");
        vm.expectRevert(err);
        reg.closeEvidence(id, "");
        vm.expectRevert(err);
        reg.cancelTransfer(id);
        vm.stopPrank();
    }

    function test_RevertWhen_CloseByNonHolder() public {
        uint256 id = _register();
        vm.expectRevert(abi.encodeWithSelector(SaksiRegistry.NotHolder.selector, id, custodianA));
        vm.prank(custodianA);
        reg.closeEvidence(id, "");
    }

    function test_RevertWhen_CloseWhileInTransfer() public {
        uint256 id = _registerAndInitiate();
        vm.expectRevert(
            abi.encodeWithSelector(SaksiRegistry.InvalidStatus.selector, id, SaksiRegistry.Status.InTransfer)
        );
        vm.prank(investigator);
        reg.closeEvidence(id, "");
    }

    function test_RevertWhen_CloseNoteTooLong() public {
        uint256 id = _register();
        vm.expectRevert(abi.encodeWithSelector(SaksiRegistry.FieldTooLong.selector, 257, 256));
        vm.prank(investigator);
        reg.closeEvidence(id, string(new bytes(257)));
    }

    // --- views ----------------------------------------------------------------

    function test_VerifyIntegrity() public {
        uint256 id = _register();
        assertTrue(reg.verifyIntegrity(id, FILE_HASH));
        assertFalse(reg.verifyIntegrity(id, TAMPERED_HASH));
    }

    function test_RevertWhen_ViewUnknownEvidence() public {
        bytes memory err = abi.encodeWithSelector(SaksiRegistry.EvidenceNotFound.selector, 7);
        vm.expectRevert(err);
        reg.getEvidence(7);
        vm.expectRevert(err);
        reg.getHistory(7);
        vm.expectRevert(err);
        reg.historyLength(7);
        vm.expectRevert(err);
        reg.verifyIntegrity(7, FILE_HASH);
    }

    // --- full scenario ----------------------------------------------------------

    function test_FullChainOfCustody() public {
        uint256 id = _register();

        vm.prank(investigator);
        reg.initiateTransfer(id, custodianA, "Ke gudang bukti");
        vm.prank(custodianA);
        reg.acceptTransfer(id, FILE_HASH);

        vm.prank(custodianA);
        reg.initiateTransfer(id, custodianB, "Ke lab forensik");
        vm.prank(custodianB);
        reg.acceptTransfer(id, TAMPERED_HASH);

        vm.prank(custodianA);
        reg.initiateTransfer(id, custodianB, "Ke lab forensik, kirim ulang");
        vm.prank(custodianB);
        reg.rejectTransfer(id, "Label tidak sesuai");

        vm.prank(custodianA);
        reg.initiateTransfer(id, custodianB, "Ke lab forensik, label diperbaiki");
        vm.prank(custodianB);
        reg.acceptTransfer(id, FILE_HASH);

        vm.prank(custodianB);
        reg.closeEvidence(id, "Analisis selesai");

        SaksiRegistry.CustodyRecord[] memory h = reg.getHistory(id);
        assertEq(h.length, 10);
        SaksiRegistry.Action[10] memory expected = [
            SaksiRegistry.Action.Registered,
            SaksiRegistry.Action.TransferInitiated,
            SaksiRegistry.Action.TransferAccepted,
            SaksiRegistry.Action.TransferInitiated,
            SaksiRegistry.Action.DiscrepancyRecorded,
            SaksiRegistry.Action.TransferInitiated,
            SaksiRegistry.Action.TransferRejected,
            SaksiRegistry.Action.TransferInitiated,
            SaksiRegistry.Action.TransferAccepted,
            SaksiRegistry.Action.Closed
        ];
        for (uint256 i; i < 10; i++) {
            assertEq(uint8(h[i].action), uint8(expected[i]));
        }
        assertEq(reg.getEvidence(id).holder, custodianB);
        assertEq(reg.getEvidence(id).discrepancyCount, 1);
    }

    // --- fuzz -----------------------------------------------------------------

    function testFuzz_Register(bytes32 fileHash, bytes32 caseRef, bytes32 metadataHash) public {
        vm.assume(fileHash != bytes32(0) && caseRef != bytes32(0));

        vm.prank(investigator);
        uint256 id = reg.registerEvidence(caseRef, metadataHash, fileHash);

        SaksiRegistry.Evidence memory e = reg.getEvidence(id);
        assertEq(e.fileHash, fileHash);
        assertEq(e.caseRef, caseRef);
        assertEq(e.metadataHash, metadataHash);
        assertEq(reg.evidenceIdByHash(fileHash), id);
        assertTrue(reg.verifyIntegrity(id, fileHash));
    }

    function testFuzz_AnyWrongHashRecordsDiscrepancy(bytes32 wrongHash) public {
        vm.assume(wrongHash != FILE_HASH);
        uint256 id = _registerAndInitiate();
        vm.expectEmit(true, true, false, true, address(reg));
        emit SaksiRegistry.DiscrepancyRecorded(id, custodianA, FILE_HASH, wrongHash);
        vm.prank(custodianA);
        assertFalse(reg.acceptTransfer(id, wrongHash));
        assertEq(reg.getEvidence(id).holder, investigator);
        assertEq(reg.getEvidence(id).discrepancyCount, 1);
    }

    function testFuzz_RevertWhen_NonPersonnelIsRecipient(address to) public {
        vm.assume(!reg.isPersonnel(to));
        uint256 id = _register();
        vm.expectRevert(abi.encodeWithSelector(SaksiRegistry.InvalidRecipient.selector, to));
        vm.prank(investigator);
        reg.initiateTransfer(id, to, "");
    }
}
