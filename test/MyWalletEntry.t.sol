// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestHelper } from "./Helper/TestHelper.t.sol";
import { MyWallet } from "../src/MyWallet.sol";
import { MyWalletStorage } from "../src/MyWalletStorage.sol";
import { UserOperation } from "account-abstraction/interfaces/UserOperation.sol";
import { ECDSA } from "openzeppelin/utils/cryptography/ECDSA.sol";
import { IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import "forge-std/console.sol";

/** 
 * @dev test interact with MyWallet through EntryPoint
 * @dev in this test, payment should be paid by the ether depositted in entry point
 */ 

contract MyWalletEntryTest is TestHelper {
    uint256 constant depositAmount = 5 ether;

    function setUp() public override {
        super.setUp();

        // deposit eth for wallet
        vm.prank(owners[0]);
        entryPoint.depositTo{value: depositAmount}(address(wallet));
        assertEq(entryPoint.balanceOf(address(wallet)), depositAmount);
    }

    function testEntrySimulateValidation() public {
        // create userOperation
        vm.startPrank(owners[0]);
        address sender = address(wallet);
        uint256 nonce = wallet.getNonce();
        bytes memory initCode = "";
        bytes memory callData = abi.encodeCall(MyWallet.entryPointTestFunction, ());
        UserOperation memory userOp = createUserOperation(sender, nonce, initCode, callData);
        // sign 
        userOp.signature = signUserOp(userOp, ownerKeys[0]);
        vm.stopPrank();

        // bundler simulate Operation
        // Successful result is ValidationResult error.
        vm.startPrank(bundler);
        vm.expectRevert();
        entryPoint.simulateValidation(userOp); // should be done offchain
        // "ValidationResult((62582, 7100000000000000, false, 0, 281474976710655, 0x), (0, 0), (0, 0), (0, 0))"
        vm.stopPrank();
    }

    function testEntryHandleOp() public {
        assertEq(address(wallet).balance, 0);
        uint256 balanceBefore = bundler.balance;

        // create userOperation
        vm.startPrank(owners[0]);
        address sender = address(wallet);
        uint256 nonce = wallet.getNonce();
        bytes memory initCode = "";
        bytes memory callData = abi.encodeCall(MyWallet.entryPointTestFunction, ());
        UserOperation memory userOp = createUserOperation(sender, nonce, initCode, callData);
        // owner sign userOperation
        userOp.signature = signUserOp(userOp, ownerKeys[0]);
        vm.stopPrank();

        // bundler send operation to entryPoint
        sendUserOp(userOp);

        // check effects
        // bundler got compensate payment
        assertGt(bundler.balance, balanceBefore);
        // paid by amount depositted in entryPoint
        assertLt(entryPoint.balanceOf(address(wallet)),depositAmount);
    }

    // submit tx by entryPoint
    function testSubmitTransactionBySignature() public {
        // owner sign transaction
        uint256 nonce = wallet.getNonce();
        bytes memory data = "";
        vm.prank(owners[0]);
        // send someone value 
        (uint8 v, bytes32 r, bytes32 s) = signTransaction(someone, 1 ether, data, nonce, block.timestamp, ownerKeys[0]);

        // create userOperation
        vm.startPrank(owners[0]);
        address sender = address(wallet);
        bytes memory initCode = "";
        bytes memory callData = abi.encodeCall(
            MyWallet.submitTransactionBySignature, 
            (
                someone, // to
                1 ether, // value
                data,
                nonce,
                block.timestamp, //expiry
                v,
                r,
                s
            ));
        
        UserOperation memory userOp = createUserOperation(sender, nonce, initCode, callData);
        // owner sign userOperation
        userOp.signature = signUserOp(userOp, ownerKeys[0]);
        vm.stopPrank();

        // bundler send operation to entryPoint
        sendUserOp(userOp);
        
        // check effects
        (MyWallet.TransactionStatus status, 
        address _to, 
        uint256 _value, 
        bytes memory _data, 
        uint256 confirmNum, 
        uint256 timestamp) = wallet.getTransactionInfo(0);
        require(status == MyWalletStorage.TransactionStatus.PENDING, "status error");
        assertEq(_to, someone);
        assertEq(_value, 1 ether);
        assertEq(_data, "");
        assertEq(confirmNum, 0);
        assertEq(timestamp, block.timestamp + timeLimit);
    }

    function testConfirmBySignature() public {
        testSubmitTransactionBySignature();

        // owner sign confirm
        uint256 nonce = wallet.getNonce();
        vm.prank(owners[0]);
        // confirm transactionIndex = 0
        (uint8 v, bytes32 r, bytes32 s) = signConfirm(0, nonce, block.timestamp, ownerKeys[0]);

        // create userOperation
        vm.startPrank(owners[0]);
        address sender = address(wallet);
        bytes memory initCode = "";
        bytes memory callData = abi.encodeCall(
            MyWallet.confirmTransactionBySignature, 
            (
                0,
                nonce,
                block.timestamp, //expiry
                v,
                r,
                s
            ));
        
        UserOperation memory userOp = createUserOperation(sender, nonce, initCode, callData);
        // owner sign userOperation
        userOp.signature = signUserOp(userOp, ownerKeys[0]);
        vm.stopPrank();

        // bundler send operation to entryPoint
        sendUserOp(userOp);

        // check effects
        ( , , , , uint256 confirmNum, ) = wallet.getTransactionInfo(0);
        assertEq(confirmNum, 1);
        assertTrue(wallet.isConfirmed(0, owners[0]));
    }

    // freeze wallet by entryPoint
    function testFreezeWalletBySignature() public {
        // owner sign freeze
        uint256 nonce = wallet.getNonce();
        vm.prank(owners[0]);
        (uint8 v, bytes32 r, bytes32 s) = signFreeze(nonce, block.timestamp, ownerKeys[0]);
        
        // create userOperation
        vm.startPrank(owners[0]);
        address sender = address(wallet);
        bytes memory initCode = "";
        bytes memory callData = abi.encodeCall(
            MyWallet.freezeWalletBySignature, 
            (
                nonce,
                block.timestamp, //expiry
                v,
                r,
                s
            ));
        
        UserOperation memory userOp = createUserOperation(sender, nonce, initCode, callData);
        // owner sign userOperation
        userOp.signature = signUserOp(userOp, ownerKeys[0]);
        vm.stopPrank();

        // bundler send operation to entryPoint
        sendUserOp(userOp);

        // check effects
        assertTrue(wallet.isFreezing());
    }

    // unfreeze wallet by entryPoint
    function testUnfreezeWalletBySignature() public {
        testFreezeWalletBySignature();

        // owner sign unfreeze
        uint256 nonce = wallet.getNonce();
        vm.prank(owners[0]);
        (uint8 v, bytes32 r, bytes32 s) = signUnfreeze(nonce, block.timestamp, ownerKeys[0]);
        
        // create userOperation
        vm.startPrank(owners[0]);
        address sender = address(wallet);
        bytes memory initCode = "";
        bytes memory callData = abi.encodeCall(
            MyWallet.unfreezeWalletBySignature, 
            (
                nonce,
                block.timestamp, //expiry
                v,
                r,
                s
            ));
        
        UserOperation memory userOp = createUserOperation(sender, nonce, initCode, callData);
        // owner sign userOperation
        userOp.signature = signUserOp(userOp, ownerKeys[0]);
        vm.stopPrank();

        // bundler send operation to entryPoint
        sendUserOp(userOp);

        // check effects
        assertTrue(wallet.unfreezeBy(0, owners[0]));
        assertEq(wallet.unfreezeCounter(), 1);
    }

    // submit recovery by entryPoint
    function testSubmitRecoveryBySignature() public {
        address newOwner = makeAddr("newOwner");
        address replacedOwner = owners[2];

        // guardian sign recovery
        uint256 nonce = wallet.getNonce();
        vm.prank(guardians[0]);
        (uint8 v, bytes32 r, bytes32 s) = signRecovery(replacedOwner, newOwner, nonce, block.timestamp, guardianKeys[0]);

        // create userOperation
        vm.startPrank(owners[0]);
        address sender = address(wallet);
        bytes memory initCode = "";
        bytes memory callData = abi.encodeCall(
            MyWallet.submitRecoveryBySignature, 
            (
                replacedOwner,
                newOwner,
                nonce,
                block.timestamp, //expiry
                v,
                r,
                s
            ));
        UserOperation memory userOp = createUserOperation(sender, nonce, initCode, callData);
        // owner sign userOperation
        userOp.signature = signUserOp(userOp, ownerKeys[0]);
        vm.stopPrank();

        // bundler send operation to entryPoint
        sendUserOp(userOp);

        // check effects
        // paid by amount depositted in entryPoint
        assertLt(entryPoint.balanceOf(address(wallet)), depositAmount);
        // recovery info
        (address addr1, address addr2, uint256 num) = wallet.getRecoveryInfo();
        assertEq(addr1, replacedOwner);
        assertEq(addr2, newOwner);
        assertEq(num, 0);
        assertTrue(wallet.isRecovering());
    }

    // support recovery by entryPoint
    function testSupportRecoveryBySignature() public {
        testSubmitRecoveryBySignature();

        // guardian sign support
        uint256 nonce = wallet.getNonce();
        vm.prank(guardians[0]);
        (uint8 v, bytes32 r, bytes32 s) = signSupport(nonce, block.timestamp, guardianKeys[0]);

        // create userOperation
        vm.startPrank(owners[0]);
        address sender = address(wallet);
        bytes memory initCode = "";
        bytes memory callData = abi.encodeCall(
            MyWallet.supportRecoveryBySignature, 
            (
                nonce,
                block.timestamp, //expiry
                v,
                r,
                s
            ));
        UserOperation memory userOp = createUserOperation(sender, nonce, initCode, callData);
        // owner sign userOperation
        userOp.signature = signUserOp(userOp, ownerKeys[0]);
        vm.stopPrank();

        // bundler send operation to entryPoint
        sendUserOp(userOp);

        // check effects
        ( , , uint256 num) = wallet.getRecoveryInfo();
        assertEq(num, 1);
        assertTrue(wallet.recoverBy(0, guardians[0]));
    }

    function testExecuteRecoveryBySignature() public {
        // submit recovery
        (address replacedOwner, address newOwner) = submitRecovery();

        // support recovery
        vm.prank(guardians[0]);
        wallet.supportRecovery();
        vm.prank(guardians[1]);
        wallet.supportRecovery();

        // owner sign executeRecovery
        uint256 nonce = wallet.getNonce();
        vm.prank(owners[0]);
        (uint8 v, bytes32 r, bytes32 s) = signExecuteRecovery(nonce, block.timestamp, ownerKeys[0]);
        
        // create userOperation
        vm.startPrank(owners[0]);
        address sender = address(wallet);
        bytes memory initCode = "";
        bytes memory callData = abi.encodeCall(
            MyWallet.executeRecoveryBySignature, 
            (
                nonce,
                block.timestamp, //expiry
                v,
                r,
                s
            ));
        
        UserOperation memory userOp = createUserOperation(sender, nonce, initCode, callData);
        // owner sign userOperation
        userOp.signature = signUserOp(userOp, ownerKeys[0]);
        vm.stopPrank();

        // bundler send operation to entryPoint
        sendUserOp(userOp);

        // check effects
        // check effects
        assertTrue(wallet.isOwner(newOwner));
        assertFalse(wallet.isOwner(replacedOwner));
        assertFalse(wallet.isRecovering());
        assertEq(wallet.recoverRound(), 1);
        (address addr1, address addr2, uint256 num) = wallet.getRecoveryInfo();
        assertEq(addr1, address(0));
        assertEq(addr2, address(0));
        assertEq(num, 0);
    }
}