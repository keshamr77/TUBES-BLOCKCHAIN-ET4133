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
///      OUTSIDER           (opsional) akun uji tanpa peran; hanya diberi saldo
///      FUND_WEI           (opsional) isi saldo akun yang saldonya di bawah nilai ini
contract Deploy is Script {
    function run() external returns (SaksiRegistry reg) {
        uint256 adminKey = vm.envUint("ADMIN_PRIVATE_KEY");
        address admin = vm.addr(adminKey);
        address investigator = vm.envAddress("INVESTIGATOR");
        address custodianA = vm.envAddress("CUSTODIAN_A");
        address custodianB = vm.envAddress("CUSTODIAN_B");
        address outsider = vm.envOr("OUTSIDER", address(0));
        uint256 fundWei = vm.envOr("FUND_WEI", uint256(0));

        vm.startBroadcast(adminKey);
        reg = new SaksiRegistry(admin);
        reg.grantRole(reg.INVESTIGATOR_ROLE(), investigator);
        reg.grantRole(reg.CUSTODIAN_ROLE(), custodianA);
        reg.grantRole(reg.CUSTODIAN_ROLE(), custodianB);

        if (fundWei > 0) {
            address[4] memory accounts = [investigator, custodianA, custodianB, outsider];
            for (uint256 i; i < accounts.length; i++) {
                if (accounts[i] != address(0) && accounts[i].balance < fundWei) {
                    (bool ok,) = payable(accounts[i]).call{value: fundWei}("");
                    require(ok, "funding failed");
                }
            }
        }
        vm.stopBroadcast();

        console.log("SaksiRegistry:", address(reg));
        console.log("Admin:", admin);
    }
}
