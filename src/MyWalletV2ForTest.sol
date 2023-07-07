// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { ReentrancyGuard } from "openzeppelin/security/ReentrancyGuard.sol";
import { MyWalletStorageV2 } from "./MyWalletStorage.sol";
import { Proxiable } from "./Proxy/Proxiable.sol";
import { Initializable } from "openzeppelin/proxy/utils/Initializable.sol";

contract MyWalletV2ForTest is Proxiable, ReentrancyGuard, Initializable, MyWalletStorageV2{
    constructor() {
        _disableInitializers();
    }

    function initializeV2() reinitializer(2) public {
        testNum = 2;
    }
}
