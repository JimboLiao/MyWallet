// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestHelper } from "./Helper/TestHelper.t.sol";
import { MyWallet } from "../src/MyWallet.sol";
import { MyWalletStorage } from "../src/MyWalletStorage.sol";
import { UserOperation } from "account-abstraction/interfaces/UserOperation.sol";


/** 
 * @dev test interact with MyWallet through EntryPoint
 */ 

/*
struct UserOperation {
        address sender;
        uint256 nonce;
        bytes initCode;
        bytes callData;
        uint256 callGasLimit;
        uint256 verificationGasLimit;
        uint256 preVerificationGas;
        uint256 maxFeePerGas;
        uint256 maxPriorityFeePerGas;
        bytes paymasterAndData;
        bytes signature;
    }
*/
contract MyWalletEntryTest is TestHelper {
    address bundler;

    function setUp() public override {
        super.setUp();

        bundler = makeAddr("bundler");
        vm.deal(bundler, INIT_BALANCE);
    }

    function testvalidateUserOp() public {
        // sign 
        vm.startPrank(owners[0]);
        UserOperation memory userOp;
        userOp.sender = address(wallet);
        userOp.nonce = 0;
        userOp.callData = abi.encodeCall(MyWallet.entryPointTestFunction, ());
        vm.stopPrank();
    }


}