// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { EnumerableSet } from  "openzeppelin/utils/structs/EnumerableSet.sol";
import { IEntryPoint } from "account-abstraction/interfaces/IEntryPoint.sol";

contract MyWalletStorage {
    
    /**********************
     *   enum 
     **********************/
    ///@notice transaction status for multisig
    enum TransactionStatus {
        PENDING,
        PASS,
        EXECUTED,
        OVERTIME
    }

    /**********************
     *   struct
     **********************/ 
    ///@notice transaction infomation
    struct Transaction {
        TransactionStatus status;
        address to; // target address to call
        uint256 value; // value with the transaction
        uint256 confirmNum; // confirmed number of multisig
        uint256 untilTimestamp; // timelimit to pass the transaction
        bytes data; // calldata
    }

    ///@notice Recovery infomation
    struct Recovery {
        address newOwner; // new owner after recovery
        address replacedOwner; // owner to be replaced
        uint256 supportNum; // number of support recovery
    }

    /**********************
     *   constant 
     **********************/
    ///@notice A time limit for multisig
    uint256 public constant overTimeLimit = 1 days;

    /// @notice type hash submit transaction
    // transactionTypeHash = keccak256("Transaction(address to,uint256 value,bytes data,uint256 nonce,uint256 expiry)");
    bytes32 public constant transactionTypeHash = 0xbc324d7cf0904e0cd603eb9343c1a9fba4b33073524cb54fb43e3d081e1fcd49;

    /// @notice type hash confirm transaction
    // confirmTypeHash = keccak256("Confirm(uint256 transactionIndex,uint256 nonce,uint256 expiry)");
    bytes32 public constant confirmTypeHash = 0x69e415fc8bf477fb310f448601509abf73ec39720f1ded109fb5f0c2404746fb;

    /// @notice type hash of submit Recovery
    // recoveryTypeHash = keccak256("Recovery(address replacedOwner,address newOwner,uint256 nonce,uint256 expiry)");
    bytes32 public constant recoveryTypeHash = 0xf22d4e9321e685dd9f081439bcea89d34c2356cae21bac61131f63aa487504b7;

    /// @notice type hash of support Recovery
    // supportTypeHash = keccak256("Support(uint256 nonce,uint256 expiry)");
    bytes32 public constant supportTypeHash = 0x1c4c70d4ea4c7f9cf28a4ab9413f346cc7a2775791591ff7a80ed20e69cc52d3;

    /// @notice type hash of support Recovery
    // executeRecoveryTypeHash = keccak256("ExecuteRecovery(uint256 nonce,uint256 expiry)");
    bytes32 public constant executeRecoveryTypeHash = 0x7d0bb67a0ad275e7f5e5fb312d6270dfd94a894fda0a7b78b615442b4f2196a7;

    /// @notice type hash of freeze wallet
    // freezeTypeHash = keccak256("Freeze(uint256 nonce,uint256 expiry)");
    bytes32 public constant freezeTypeHash = 0x4bd89d51172e4e922fc8ee675198fe0d119b7703fab3d1cc5196b5260050f9ab;

    /// @notice type hash of unfreeze wallet
    // unfreezeTypeHash = keccak256("Unfreeze(uint256 nonce,uint256 expiry)");
    bytes32 public constant unfreezeTypeHash = 0x476ca6dfd610f443acd2e659c0cddeafa57c87e0871a584dd4a4b19be27dda57;

    /**********************
     *   variables
     **********************/
    /// @notice true if wallet is frozen
    bool public isFreezing;

    /// @notice true if wallet is in recovery process
    bool public isRecovering;

    /// @notice owners
    EnumerableSet.AddressSet internal owners;

    /// @notice whitelist addresses
    EnumerableSet.AddressSet internal whiteList;

    /// @notice guardian hashes to hide the id of guardians undil recovery
    EnumerableSet.Bytes32Set internal guardianHashes;

    /// @notice record every transaction submitted
    Transaction[] internal transactionList;

    /// @notice submitted recovery infomation
    Recovery internal recoveryProposed;

    /// @notice entry point of ERC-4337
    IEntryPoint internal immutable entryPointErc4337;

    /// @notice domain seperator for EIP-712
    bytes32 internal domainSeparator;

    /// @notice threshold for multisig and unfreeze
    uint256 public leastConfirmThreshold;

    /// @notice threshold for recovery
    uint256 public recoverThreshold;

    /// @notice unfreeze counter of current round
    uint256 public unfreezeCounter;

    /// @notice current round of freeze
    uint256 public unfreezeRound;

    /// @notice current round of recovery
    uint256 public recoverRound;

    /// @notice true if already confirm tx
    /// @dev tx index => owner address => bool
    mapping(uint256 => mapping(address => bool)) public isConfirmed;

    /// @notice true if already unfreeze by owner
    /// @dev unfreezeRound => owner address => bool
    mapping(uint256 => mapping(address => bool)) public unfreezeBy;

    /// @notice true if already support recovery by guardian
    /// @dev recoveryRound => guardian address => bool
    mapping(uint256 => mapping(address => bool)) public recoverBy;

    constructor(IEntryPoint _entryPoint){
        entryPointErc4337 = _entryPoint;
    }
}

contract MyWalletStorageV2 is MyWalletStorage {
    constructor(IEntryPoint _entryPoint) MyWalletStorage(_entryPoint) {}

    uint256 public testNum;
}