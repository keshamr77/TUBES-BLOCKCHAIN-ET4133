// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {AccessControl, IAccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/// @notice Small contract used only to smoke-test the toolchain (not the SAKSI contract).
contract SmokeRegistry is AccessControl, Pausable {
    bytes32 public constant RECORDER_ROLE = keccak256("RECORDER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    bytes32 public merkleRoot;
    uint256 public count;
    mapping(bytes32 => bool) public recorded;

    event Recorded(bytes32 indexed id, address indexed by);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(RECORDER_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
    }

    function record(bytes32 id) external onlyRole(RECORDER_ROLE) whenNotPaused {
        recorded[id] = true;
        count++;
        emit Recorded(id, msg.sender);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function setMerkleRoot(bytes32 root) external onlyRole(DEFAULT_ADMIN_ROLE) {
        merkleRoot = root;
    }

    function verify(bytes32[] calldata proof, bytes32 leaf) external view returns (bool) {
        return MerkleProof.verifyCalldata(proof, merkleRoot, leaf);
    }
}

contract SetupTest is Test {
    SmokeRegistry internal reg;
    address internal admin = makeAddr("admin");
    address internal recorder = makeAddr("recorder");
    address internal stranger = makeAddr("stranger");

    function setUp() public {
        reg = new SmokeRegistry(admin);
        bytes32 role = reg.RECORDER_ROLE();
        vm.prank(admin);
        reg.grantRole(role, recorder);
    }

    function test_RoleHolderCanRecord() public {
        vm.expectEmit(true, true, false, false, address(reg));
        emit SmokeRegistry.Recorded(keccak256("item-1"), recorder);
        vm.prank(recorder);
        reg.record(keccak256("item-1"));
        assertTrue(reg.recorded(keccak256("item-1")));
        assertEq(reg.count(), 1);
    }

    function test_RevertWhen_CallerLacksRole() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, reg.RECORDER_ROLE()
            )
        );
        vm.prank(stranger);
        reg.record(keccak256("item-1"));
    }

    function test_RevertWhen_Paused() public {
        vm.prank(admin);
        reg.pause();
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(recorder);
        reg.record(keccak256("item-1"));
    }

    function testFuzz_RecordAnyId(bytes32 id, address caller) public {
        vm.assume(caller != address(0));
        bytes32 role = reg.RECORDER_ROLE();
        vm.prank(admin);
        reg.grantRole(role, caller);
        vm.prank(caller);
        reg.record(id);
        assertTrue(reg.recorded(id));
        assertEq(reg.count(), 1);
    }

    function test_MerkleProofVerifies() public {
        bytes32[4] memory leaves;
        for (uint256 i; i < 4; i++) {
            leaves[i] = keccak256(bytes.concat(keccak256(abi.encode(i))));
        }
        bytes32 left = _hashPair(leaves[0], leaves[1]);
        bytes32 right = _hashPair(leaves[2], leaves[3]);
        bytes32 root = _hashPair(left, right);

        vm.prank(admin);
        reg.setMerkleRoot(root);

        bytes32[] memory proof = new bytes32[](2);
        proof[0] = leaves[1];
        proof[1] = right;
        assertTrue(reg.verify(proof, leaves[0]));
        assertFalse(reg.verify(proof, leaves[2]));
    }

    function _hashPair(bytes32 a, bytes32 b) private pure returns (bytes32) {
        return a < b ? keccak256(abi.encode(a, b)) : keccak256(abi.encode(b, a));
    }
}
