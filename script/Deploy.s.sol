// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {SaksiRegistry} from "../src/SaksiRegistry.sol";

/// @notice Deploy SaksiRegistry dan siapkan peran untuk simulasi.
/// @dev Variabel lingkungan:
///      ADMIN_PRIVATE_KEY  kunci admin (deployer)
///      INVESTIGATOR       alamat penyidik
///      CUSTODIAN_A        alamat kustodian A
///      CUSTODIAN_B        alamat kustodian B
///      FUND_WEI           (opsional) isi saldo akun yang saldonya di bawah nilai ini
contract Deploy is Script {
    function run() external returns (SaksiRegistry reg) {
        uint256 adminKey = vm.envUint("ADMIN_PRIVATE_KEY");
        address admin = vm.addr(adminKey);
        address investigator = vm.envAddress("INVESTIGATOR");
        address custodianA = vm.envAddress("CUSTODIAN_A");
        address custodianB = vm.envAddress("CUSTODIAN_B");
        uint256 fundWei = vm.envOr("FUND_WEI", uint256(0));

        vm.startBroadcast(adminKey);
        reg = new SaksiRegistry(admin);
        reg.grantRole(reg.INVESTIGATOR_ROLE(), investigator);
        reg.grantRole(reg.CUSTODIAN_ROLE(), custodianA);
        reg.grantRole(reg.CUSTODIAN_ROLE(), custodianB);

        if (fundWei > 0) {
            address[3] memory personnel = [investigator, custodianA, custodianB];
            for (uint256 i; i < personnel.length; i++) {
                if (personnel[i].balance < fundWei) {
                    (bool ok,) = payable(personnel[i]).call{value: fundWei}("");
                    require(ok, "funding failed");
                }
            }
        }
        vm.stopBroadcast();

        console.log("SaksiRegistry:", address(reg));
        console.log("Admin:", admin);
    }
}
