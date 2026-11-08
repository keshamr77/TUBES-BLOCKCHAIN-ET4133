// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {SaksiRegistry} from "../src/SaksiRegistry.sol";

/// @notice Menjalankan aksi acak terhadap SaksiRegistry atas nama beberapa aktor
///         dan menyimpan "ghost state" untuk diperiksa oleh uji invariant.
contract SaksiHandler is Test {
    SaksiRegistry public reg;
    address[] public actors;

    uint256 public ghostRegistered;
    mapping(uint256 id => bytes32) public ghostHash;
    mapping(uint256 id => uint256) public ghostHistoryLength;
    mapping(uint256 id => bool) public ghostClosed;
    mapping(uint256 id => address) public ghostHolderAtClose;
    mapping(uint256 id => uint256) public ghostHistoryAtClose;

    bool public historyShrank;

    uint256 internal nonce;

    constructor(SaksiRegistry reg_, address[] memory actors_) {
        reg = reg_;
        actors = actors_;
    }

    /// @dev Dicatat setelah setiap aksi: riwayat tidak boleh pernah memendek.
    modifier tracksHistory(uint256 idSeed) {
        _;
        uint256 id = _existingId(idSeed);
        if (id <= reg.evidenceCount()) {
            uint256 len = reg.historyLength(id);
            if (len < ghostHistoryLength[id]) historyShrank = true;
            ghostHistoryLength[id] = len;
        }
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function _existingId(uint256 seed) internal view returns (uint256) {
        uint256 count = reg.evidenceCount();
        return count == 0 ? 1 : (seed % count) + 1;
    }

    function register(uint256 actorSeed) external {
        address actor = _actor(actorSeed);
        bytes32 h = keccak256(abi.encode("berkas", nonce++));
        vm.prank(actor);
        try reg.registerEvidence("LP/INV/2026", "bukti uji", h) returns (uint256 id) {
            ghostRegistered++;
            ghostHash[id] = h;
        } catch {}
    }

    function initiate(uint256 actorSeed, uint256 idSeed, uint256 toSeed) external tracksHistory(idSeed) {
        uint256 id = _existingId(idSeed);
        vm.prank(_actor(actorSeed));
        try reg.initiateTransfer(id, _actor(toSeed), "uji") {} catch {}
    }

    function accept(uint256 actorSeed, uint256 idSeed, bool useCorrectHash) external tracksHistory(idSeed) {
        uint256 id = _existingId(idSeed);
        bytes32 h = useCorrectHash ? ghostHash[id] : keccak256("salah");
        vm.prank(_actor(actorSeed));
        try reg.acceptTransfer(id, h) {} catch {}
    }

    function reject(uint256 actorSeed, uint256 idSeed) external tracksHistory(idSeed) {
        uint256 id = _existingId(idSeed);
        vm.prank(_actor(actorSeed));
        try reg.rejectTransfer(id, "tolak") {} catch {}
    }

    function cancel(uint256 actorSeed, uint256 idSeed) external tracksHistory(idSeed) {
        uint256 id = _existingId(idSeed);
        vm.prank(_actor(actorSeed));
        try reg.cancelTransfer(id) {} catch {}
    }

    function close(uint256 actorSeed, uint256 idSeed) external tracksHistory(idSeed) {
        uint256 id = _existingId(idSeed);
        vm.prank(_actor(actorSeed));
        try reg.closeEvidence(id, "selesai") {
            ghostClosed[id] = true;
            ghostHolderAtClose[id] = reg.getEvidence(id).holder;
            ghostHistoryAtClose[id] = reg.historyLength(id);
        } catch {}
    }
}

/// @notice Uji invariant SaksiRegistry.
contract SaksiRegistryInvariantTest is Test {
    SaksiRegistry internal reg;
    SaksiHandler internal handler;

    function setUp() public {
        address admin = makeAddr("admin");
        address[] memory actors = new address[](5);
        actors[0] = makeAddr("investigator1");
        actors[1] = makeAddr("investigator2");
        actors[2] = makeAddr("custodianA");
        actors[3] = makeAddr("custodianB");
        actors[4] = makeAddr("outsider");

        reg = new SaksiRegistry(admin);
        vm.startPrank(admin);
        reg.grantRole(reg.INVESTIGATOR_ROLE(), actors[0]);
        reg.grantRole(reg.INVESTIGATOR_ROLE(), actors[1]);
        reg.grantRole(reg.CUSTODIAN_ROLE(), actors[2]);
        reg.grantRole(reg.CUSTODIAN_ROLE(), actors[3]);
        vm.stopPrank();

        handler = new SaksiHandler(reg, actors);
        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = SaksiHandler.register.selector;
        selectors[1] = SaksiHandler.initiate.selector;
        selectors[2] = SaksiHandler.accept.selector;
        selectors[3] = SaksiHandler.reject.selector;
        selectors[4] = SaksiHandler.cancel.selector;
        selectors[5] = SaksiHandler.close.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// Jumlah bukti sama dengan jumlah pendaftaran yang berhasil.
    function invariant_CountMatchesRegistrations() public view {
        assertEq(reg.evidenceCount(), handler.ghostRegistered());
    }

    /// Hash bukti tidak pernah berubah dan pemegang selalu terisi oleh personel.
    function invariant_HashImmutableAndHolderSet() public view {
        for (uint256 id = 1; id <= reg.evidenceCount(); id++) {
            SaksiRegistry.Evidence memory e = reg.getEvidence(id);
            assertEq(e.fileHash, handler.ghostHash(id));
            assertEq(reg.evidenceIdByHash(e.fileHash), id);
            assertTrue(e.holder != address(0));
        }
    }

    /// Status InTransfer jika dan hanya jika ada calon penerima, dan penerima bukan pemegang.
    function invariant_PendingRecipientConsistent() public view {
        for (uint256 id = 1; id <= reg.evidenceCount(); id++) {
            SaksiRegistry.Evidence memory e = reg.getEvidence(id);
            bool inTransfer = e.status == SaksiRegistry.Status.InTransfer;
            assertEq(inTransfer, e.pendingRecipient != address(0));
            if (inTransfer) assertTrue(e.pendingRecipient != e.holder);
        }
    }

    /// Riwayat hanya bertambah; bukti Closed tidak pernah berubah lagi.
    function invariant_HistoryAppendOnlyAndClosedIsFinal() public view {
        assertFalse(handler.historyShrank());
        for (uint256 id = 1; id <= reg.evidenceCount(); id++) {
            uint256 len = reg.historyLength(id);
            assertGe(len, handler.ghostHistoryLength(id));
            assertGe(len, 1);

            if (handler.ghostClosed(id)) {
                SaksiRegistry.Evidence memory e = reg.getEvidence(id);
                assertEq(uint8(e.status), uint8(SaksiRegistry.Status.Closed));
                assertEq(e.holder, handler.ghostHolderAtClose(id));
                assertEq(len, handler.ghostHistoryAtClose(id));
            }
        }
    }
}
