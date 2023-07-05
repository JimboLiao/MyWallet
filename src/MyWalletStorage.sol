// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

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
        uint256 replacedOwnerIndex; // index of owner to be replaced
        uint256 supportNum; // number of support recovery
    }

    /**********************
     *   constant 
     **********************/
    ///@notice A time limit for multisig
    uint256 public constant overTimeLimit = 1 days;

    /**********************
     *   variables
     **********************/
    /// @notice true if wallet is frozen
    bool public isFreezing;

    /// @notice true if wallet is in recovery process
    bool public isRecovering;

    address[] internal owners;
    // todo need this?
    address[] internal whiteList;

    /// @notice guardian hashes to hide the id of guardians undil recovery
    // todo need this?
    bytes32[] internal guardianHashes;

    /// @notice record every transaction submitted
    Transaction[] internal transactionList;

    /// @notice submitted recovery infomation
    Recovery internal recoveryProposed;

    /// @notice threshold for multisig and unfreeze
    uint256 public leastConfirmThreshold;

    /// @notice threshold for recovery
    uint256 public recoverThreshold;

    mapping(address => bool) public isOwner;
    mapping(address => bool) public isWhiteList;
    mapping(bytes32 => bool) public isGuardian;
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
}