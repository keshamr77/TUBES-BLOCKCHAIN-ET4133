// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/// @title SaksiRegistry
/// @notice Pencatatan serah-terima (chain of custody) bukti digital.
/// @dev Hanya hash yang disimpan: hash SHA-256 berkas, hash nomor perkara, dan hash deskripsi.
///      Berkas bukti dan teks perkara tetap di luar rantai.
///      Serah-terima memakai dua langkah: pemegang memulai, penerima mengonfirmasi
///      dengan mengirim ulang hash berkas. Jika hash berbeda, ketidakcocokan dicatat
///      permanen di rantai (bukan di-revert) dan serah-terima dibatalkan.
contract SaksiRegistry is AccessControl, Pausable {
    /// @notice Peran penyidik: boleh mendaftarkan bukti baru.
    bytes32 public constant INVESTIGATOR_ROLE = keccak256("INVESTIGATOR_ROLE");
    /// @notice Peran kustodian: boleh menerima, menyimpan, dan menyerahkan bukti.
    bytes32 public constant CUSTODIAN_ROLE = keccak256("CUSTODIAN_ROLE");

    /// @notice Panjang maksimal catatan serah-terima (byte).
    uint256 public constant MAX_TEXT_LENGTH = 256;

    enum Status {
        None,
        Stored,
        InTransfer,
        Closed
    }

    enum Action {
        Registered,
        TransferInitiated,
        TransferAccepted,
        TransferRejected,
        TransferCancelled,
        Closed,
        DiscrepancyRecorded
    }

    struct Evidence {
        /// keccak256 nomor perkara yang dinormalisasi (trim + huruf besar).
        bytes32 caseRef;
        /// keccak256 deskripsi; bytes32(0) jika tanpa deskripsi.
        bytes32 metadataHash;
        bytes32 fileHash;
        address holder;
        address pendingRecipient;
        Status status;
        uint64 registeredAt;
        /// Jumlah upaya serah-terima dengan hash berkas yang tidak cocok. Tidak pernah berkurang.
        uint256 discrepancyCount;
    }

    struct CustodyRecord {
        Action action;
        address actor;
        address counterparty;
        uint64 timestamp;
        /// Catatan teks. Untuk DiscrepancyRecorded berisi hash berkas yang diserahkan (hex).
        string note;
    }

    /// @notice Jumlah bukti terdaftar; id bukti dimulai dari 1.
    uint256 public evidenceCount;
    /// @notice Id bukti untuk setiap hash berkas (0 jika belum terdaftar).
    mapping(bytes32 fileHash => uint256 id) public evidenceIdByHash;

    mapping(uint256 id => Evidence) private _evidence;
    mapping(uint256 id => CustodyRecord[]) private _history;

    event EvidenceRegistered(
        uint256 indexed id, address indexed holder, bytes32 indexed caseRef, bytes32 fileHash, bytes32 metadataHash
    );
    event TransferInitiated(uint256 indexed id, address indexed from, address indexed to, string note);
    event TransferAccepted(uint256 indexed id, address indexed from, address indexed to);
    event TransferRejected(uint256 indexed id, address indexed from, address indexed by, string note);
    event TransferCancelled(uint256 indexed id, address indexed by, address indexed to);
    event EvidenceClosed(uint256 indexed id, address indexed by, string note);
    /// @notice Penerima menyerahkan berkas yang hash-nya berbeda dari yang terdaftar.
    event DiscrepancyRecorded(uint256 indexed id, address indexed by, bytes32 expected, bytes32 provided);

    error EvidenceNotFound(uint256 id);
    error NotPersonnel(address account);
    error NotHolder(uint256 id, address caller);
    error NotPendingRecipient(uint256 id, address caller);
    error InvalidStatus(uint256 id, Status current);
    error InvalidRecipient(address recipient);
    error DuplicateEvidence(bytes32 fileHash, uint256 existingId);
    error EmptyField();
    error FieldTooLong(uint256 length, uint256 max);

    /// @param admin Alamat yang menerima peran admin.
    constructor(address admin) {
        if (admin == address(0)) revert InvalidRecipient(admin);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    // ---------------------------------------------------------------------
    // Admin
    // ---------------------------------------------------------------------

    /// @notice Menghentikan sementara semua perubahan data bukti.
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /// @notice Melanjutkan kembali sistem setelah dijeda.
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    // ---------------------------------------------------------------------
    // Alur bukti
    // ---------------------------------------------------------------------

    /// @notice Mendaftarkan bukti baru. Pemanggil menjadi pemegang pertama.
    /// @param caseRef keccak256 nomor perkara yang dinormalisasi (dihitung di luar rantai).
    /// @param metadataHash keccak256 deskripsi bukti, atau bytes32(0) jika tanpa deskripsi.
    /// @param fileHash Hash SHA-256 berkas bukti.
    /// @return id Id bukti baru.
    function registerEvidence(bytes32 caseRef, bytes32 metadataHash, bytes32 fileHash)
        external
        onlyRole(INVESTIGATOR_ROLE)
        whenNotPaused
        returns (uint256 id)
    {
        if (fileHash == bytes32(0) || caseRef == bytes32(0)) revert EmptyField();
        uint256 existing = evidenceIdByHash[fileHash];
        if (existing != 0) revert DuplicateEvidence(fileHash, existing);

        id = ++evidenceCount;
        evidenceIdByHash[fileHash] = id;
        _evidence[id] = Evidence({
            caseRef: caseRef,
            metadataHash: metadataHash,
            fileHash: fileHash,
            holder: msg.sender,
            pendingRecipient: address(0),
            status: Status.Stored,
            // casting to 'uint64' is safe because block timestamps fit in uint64 until ~year 584 billion
            // forge-lint: disable-next-line(unsafe-typecast)
            registeredAt: uint64(block.timestamp),
            discrepancyCount: 0
        });
        _record(id, Action.Registered, address(0), "");
        emit EvidenceRegistered(id, msg.sender, caseRef, fileHash, metadataHash);
    }

    /// @notice Pemegang memulai serah-terima ke personel lain.
    function initiateTransfer(uint256 id, address to, string calldata note) external whenNotPaused {
        Evidence storage e = _requireStatus(id, Status.Stored);
        _requireHolder(e, id);
        if (to == msg.sender || !isPersonnel(to)) revert InvalidRecipient(to);
        _checkLength(bytes(note).length, MAX_TEXT_LENGTH);

        e.pendingRecipient = to;
        e.status = Status.InTransfer;
        _record(id, Action.TransferInitiated, to, note);
        emit TransferInitiated(id, msg.sender, to, note);
    }

    /// @notice Calon penerima mengonfirmasi serah-terima dengan hash berkas yang ia terima.
    /// @dev Jika hash cocok, pemegang berpindah ke penerima. Jika tidak cocok, transaksi tetap
    ///      berhasil: ketidakcocokan dicatat di riwayat dan event, discrepancyCount bertambah,
    ///      dan serah-terima dibatalkan (bukti tetap pada pengirim, status kembali Stored).
    /// @param fileHash Hash SHA-256 berkas yang diterima, dihitung sendiri oleh penerima.
    /// @return accepted True jika bukti berpindah, false jika ketidakcocokan dicatat.
    function acceptTransfer(uint256 id, bytes32 fileHash) external whenNotPaused returns (bool accepted) {
        Evidence storage e = _requireStatus(id, Status.InTransfer);
        _requirePendingRecipient(e, id);

        address from = e.holder;
        e.pendingRecipient = address(0);
        e.status = Status.Stored;

        bytes32 expected = e.fileHash;
        if (fileHash != expected) {
            ++e.discrepancyCount;
            _record(id, Action.DiscrepancyRecorded, from, Strings.toHexString(uint256(fileHash), 32));
            emit DiscrepancyRecorded(id, msg.sender, expected, fileHash);
            return false;
        }

        e.holder = msg.sender;
        _record(id, Action.TransferAccepted, from, "");
        emit TransferAccepted(id, from, msg.sender);
        return true;
    }

    /// @notice Calon penerima menolak serah-terima; bukti tetap pada pengirim.
    function rejectTransfer(uint256 id, string calldata note) external whenNotPaused {
        Evidence storage e = _requireStatus(id, Status.InTransfer);
        _requirePendingRecipient(e, id);
        _checkLength(bytes(note).length, MAX_TEXT_LENGTH);

        address from = e.holder;
        e.pendingRecipient = address(0);
        e.status = Status.Stored;
        _record(id, Action.TransferRejected, from, note);
        emit TransferRejected(id, from, msg.sender, note);
    }

    /// @notice Pemegang membatalkan serah-terima yang belum diterima.
    function cancelTransfer(uint256 id) external whenNotPaused {
        Evidence storage e = _requireStatus(id, Status.InTransfer);
        _requireHolder(e, id);

        address to = e.pendingRecipient;
        e.pendingRecipient = address(0);
        e.status = Status.Stored;
        _record(id, Action.TransferCancelled, to, "");
        emit TransferCancelled(id, msg.sender, to);
    }

    /// @notice Pemegang menutup bukti (misalnya perkara selesai). Status ini final.
    function closeEvidence(uint256 id, string calldata note) external whenNotPaused {
        Evidence storage e = _requireStatus(id, Status.Stored);
        _requireHolder(e, id);
        _checkLength(bytes(note).length, MAX_TEXT_LENGTH);

        e.status = Status.Closed;
        _record(id, Action.Closed, address(0), note);
        emit EvidenceClosed(id, msg.sender, note);
    }

    // ---------------------------------------------------------------------
    // Baca data
    // ---------------------------------------------------------------------

    /// @notice Mengembalikan data bukti.
    function getEvidence(uint256 id) external view returns (Evidence memory) {
        return _requireExists(id);
    }

    /// @notice Mengembalikan seluruh riwayat serah-terima bukti.
    function getHistory(uint256 id) external view returns (CustodyRecord[] memory) {
        _requireExists(id);
        return _history[id];
    }

    /// @notice Jumlah catatan riwayat bukti.
    function historyLength(uint256 id) external view returns (uint256) {
        _requireExists(id);
        return _history[id].length;
    }

    /// @notice Memeriksa apakah hash berkas sama dengan hash yang terdaftar.
    function verifyIntegrity(uint256 id, bytes32 fileHash) external view returns (bool) {
        return _requireExists(id).fileHash == fileHash;
    }

    /// @notice True jika akun adalah penyidik atau kustodian.
    function isPersonnel(address account) public view returns (bool) {
        return hasRole(INVESTIGATOR_ROLE, account) || hasRole(CUSTODIAN_ROLE, account);
    }

    // ---------------------------------------------------------------------
    // Internal
    // ---------------------------------------------------------------------

    function _requireExists(uint256 id) private view returns (Evidence storage e) {
        e = _evidence[id];
        if (e.status == Status.None) revert EvidenceNotFound(id);
    }

    function _requireStatus(uint256 id, Status expected) private view returns (Evidence storage e) {
        e = _requireExists(id);
        if (e.status != expected) revert InvalidStatus(id, e.status);
    }

    function _requireHolder(Evidence storage e, uint256 id) private view {
        if (e.holder != msg.sender) revert NotHolder(id, msg.sender);
        if (!isPersonnel(msg.sender)) revert NotPersonnel(msg.sender);
    }

    function _requirePendingRecipient(Evidence storage e, uint256 id) private view {
        if (e.pendingRecipient != msg.sender) revert NotPendingRecipient(id, msg.sender);
        if (!isPersonnel(msg.sender)) revert NotPersonnel(msg.sender);
    }

    function _checkLength(uint256 length, uint256 max) private pure {
        if (length > max) revert FieldTooLong(length, max);
    }

    function _record(uint256 id, Action action, address counterparty, string memory note) private {
        _history[id].push(
            CustodyRecord({
                action: action,
                actor: msg.sender,
                counterparty: counterparty,
                // casting to 'uint64' is safe because block timestamps fit in uint64 until ~year 584 billion
                // forge-lint: disable-next-line(unsafe-typecast)
                timestamp: uint64(block.timestamp),
                note: note
            })
        );
    }
}
