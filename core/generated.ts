import {
  createUseReadContract,
  createUseWriteContract,
  createUseSimulateContract,
  createUseWatchContractEvent,
} from 'wagmi/codegen'

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Factory
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

export const factoryAbi = [
  {
    type: 'constructor',
    inputs: [
      { name: 'receiptClone_', type: 'address' },
      { name: 'optionClone_', type: 'address' },
    ],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'DEFAULT_EXERCISE_WINDOW',
    outputs: [{ type: 'uint40' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'OPTION_CLONE',
    outputs: [{ type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'RECEIPT_CLONE',
    outputs: [{ type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'exercisor', type: 'address' },
      { name: 'allowed', type: 'bool' },
    ],
    name: 'allowExercise',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'token', type: 'address' },
      { name: 'owner_', type: 'address' },
    ],
    name: 'allowance',
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'token', type: 'address' },
      { name: 'amount', type: 'uint256' },
    ],
    name: 'approve',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'operator', type: 'address' },
      { name: 'approved', type: 'bool' },
    ],
    name: 'approveOperator',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'owner_', type: 'address' },
      { name: 'operator', type: 'address' },
    ],
    name: 'approvedOperator',
    outputs: [{ type: 'bool' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: '', type: 'address' }],
    name: 'autoMintBurn',
    outputs: [{ type: 'bool' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: 'token', type: 'address' }],
    name: 'blockToken',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [{ name: '', type: 'address' }],
    name: 'blocklist',
    outputs: [{ type: 'bool' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      {
        name: 'p',
        type: 'tuple',
        components: [
          { name: 'collateral', type: 'address' },
          { name: 'consideration', type: 'address' },
          { name: 'expirationDate', type: 'uint40' },
          { name: 'strike', type: 'uint96' },
          { name: 'isPut', type: 'bool' },
          { name: 'isEuro', type: 'bool' },
          { name: 'windowSeconds', type: 'uint40' },
        ],
      },
    ],
    name: 'createOption',
    outputs: [{ type: 'address' }],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      {
        name: 'params',
        type: 'tuple[]',
        components: [
          { name: 'collateral', type: 'address' },
          { name: 'consideration', type: 'address' },
          { name: 'expirationDate', type: 'uint40' },
          { name: 'strike', type: 'uint96' },
          { name: 'isPut', type: 'bool' },
          { name: 'isEuro', type: 'bool' },
          { name: 'windowSeconds', type: 'uint40' },
        ],
      },
    ],
    name: 'createOptions',
    outputs: [{ name: 'result', type: 'address[]' }],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [{ name: 'enabled', type: 'bool' }],
    name: 'enableAutoMintBurn',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'holder', type: 'address' },
      { name: 'exercisor', type: 'address' },
    ],
    name: 'exerciseAllowed',
    outputs: [{ type: 'bool' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: 'token', type: 'address' }],
    name: 'isBlocked',
    outputs: [{ type: 'bool' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: '', type: 'address' }],
    name: 'options',
    outputs: [{ type: 'bool' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'owner',
    outputs: [{ type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: '', type: 'address' }],
    name: 'receipts',
    outputs: [{ type: 'bool' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'renounceOwnership',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'from', type: 'address' },
      { name: 'to', type: 'address' },
      { name: 'amount', type: 'uint160' },
      { name: 'token', type: 'address' },
    ],
    name: 'transferFrom',
    outputs: [{ type: 'bool' }],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [{ name: 'newOwner', type: 'address' }],
    name: 'transferOwnership',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [{ name: 'token', type: 'address' }],
    name: 'unblockToken',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'event',
    inputs: [
      { name: 'token', type: 'address', indexed: true },
      { name: 'owner', type: 'address', indexed: true },
      { name: 'amount', type: 'uint256' },
    ],
    name: 'Approval',
  },
  {
    type: 'event',
    inputs: [
      { name: 'account', type: 'address', indexed: true },
      { name: 'enabled', type: 'bool' },
    ],
    name: 'AutoMintBurnUpdated',
  },
  {
    type: 'event',
    inputs: [
      { name: 'holder', type: 'address', indexed: true },
      { name: 'exercisor', type: 'address', indexed: true },
      { name: 'allowed', type: 'bool' },
    ],
    name: 'ExerciseApproval',
  },
  {
    type: 'event',
    inputs: [
      { name: 'owner', type: 'address', indexed: true },
      { name: 'operator', type: 'address', indexed: true },
      { name: 'approved', type: 'bool' },
    ],
    name: 'OperatorApproval',
  },
  {
    type: 'event',
    inputs: [
      { name: 'collateral', type: 'address', indexed: true },
      { name: 'consideration', type: 'address', indexed: true },
      { name: 'expirationDate', type: 'uint40' },
      { name: 'strike', type: 'uint96' },
      { name: 'isPut', type: 'bool' },
      { name: 'isEuro', type: 'bool' },
      { name: 'windowSeconds', type: 'uint40' },
      { name: 'option', type: 'address', indexed: true },
      { name: 'receipt', type: 'address' },
    ],
    name: 'OptionCreated',
  },
  {
    type: 'event',
    inputs: [
      { name: 'token', type: 'address' },
      { name: 'blocked', type: 'bool' },
    ],
    name: 'TokenBlocked',
  },
  { type: 'error', inputs: [], name: 'BlocklistedToken' },
  { type: 'error', inputs: [], name: 'FailedDeployment' },
  { type: 'error', inputs: [], name: 'InsufficientAllowance' },
  {
    type: 'error',
    inputs: [
      { name: 'balance', type: 'uint256' },
      { name: 'needed', type: 'uint256' },
    ],
    name: 'InsufficientBalance',
  },
  { type: 'error', inputs: [], name: 'InvalidAddress' },
  { type: 'error', inputs: [], name: 'InvalidTokens' },
  { type: 'error', inputs: [], name: 'ReentrancyGuardReentrantCall' },
  {
    type: 'error',
    inputs: [{ name: 'token', type: 'address' }],
    name: 'SafeERC20FailedOperation',
  },
] as const

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Option
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

export const optionAbi = [
  {
    type: 'constructor',
    inputs: [
      { name: 'name_', type: 'string' },
      { name: 'symbol_', type: 'string' },
    ],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'owner', type: 'address' },
      { name: 'spender', type: 'address' },
    ],
    name: 'allowance',
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'spender', type: 'address' },
      { name: 'value', type: 'uint256' },
    ],
    name: 'approve',
    outputs: [{ type: 'bool' }],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [{ name: 'account', type: 'address' }],
    name: 'balanceOf',
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: 'account', type: 'address' }],
    name: 'balancesOf',
    outputs: [
      {
        type: 'tuple',
        components: [
          { name: 'collateral', type: 'uint256' },
          { name: 'consideration', type: 'uint256' },
          { name: 'option', type: 'uint256' },
          { name: 'receipt', type: 'uint256' },
        ],
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: 'amount', type: 'uint256' }],
    name: 'burn',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'collateral',
    outputs: [{ type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'consideration',
    outputs: [{ type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'decimals',
    outputs: [{ type: 'uint8' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'details',
    outputs: [
      {
        type: 'tuple',
        components: [
          { name: 'option', type: 'address' },
          { name: 'receipt', type: 'address' },
          {
            name: 'collateral',
            type: 'tuple',
            components: [
              { name: 'address_', type: 'address' },
              { name: 'name', type: 'string' },
              { name: 'symbol', type: 'string' },
              { name: 'decimals', type: 'uint8' },
            ],
          },
          {
            name: 'consideration',
            type: 'tuple',
            components: [
              { name: 'address_', type: 'address' },
              { name: 'name', type: 'string' },
              { name: 'symbol', type: 'string' },
              { name: 'decimals', type: 'uint8' },
            ],
          },
          { name: 'expiration', type: 'uint256' },
          { name: 'strike', type: 'uint256' },
          { name: 'isPut', type: 'bool' },
          { name: 'isEuro', type: 'bool' },
          { name: 'exerciseDeadline', type: 'uint40' },
        ],
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: 'amount', type: 'uint256' }],
    name: 'exercise',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'holders', type: 'address[]' },
      { name: 'amounts', type: 'uint256[]' },
    ],
    name: 'exercise',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'holder', type: 'address' },
      { name: 'amount', type: 'uint256' },
    ],
    name: 'exercise',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'exerciseDeadline',
    outputs: [{ type: 'uint40' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'expirationDate',
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'factory',
    outputs: [{ type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'receipt_', type: 'address' },
      { name: 'owner_', type: 'address' },
    ],
    name: 'init',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'isEuro',
    outputs: [{ type: 'bool' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'isPut',
    outputs: [{ type: 'bool' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'lock',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'account', type: 'address' },
      { name: 'amount', type: 'uint256' },
    ],
    name: 'mint',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [{ name: 'amount', type: 'uint256' }],
    name: 'mint',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'name',
    outputs: [{ type: 'string' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'owner',
    outputs: [{ type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'receipt',
    outputs: [{ type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'renounceOwnership',
    outputs: [],
    stateMutability: 'pure',
  },
  {
    type: 'function',
    inputs: [],
    name: 'strike',
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'symbol',
    outputs: [{ type: 'string' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'totalSupply',
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'to', type: 'address' },
      { name: 'amount', type: 'uint256' },
    ],
    name: 'transfer',
    outputs: [{ type: 'bool' }],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'from', type: 'address' },
      { name: 'to', type: 'address' },
      { name: 'amount', type: 'uint256' },
    ],
    name: 'transferFrom',
    outputs: [{ type: 'bool' }],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [{ name: 'newOwner', type: 'address' }],
    name: 'transferOwnership',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'unlock',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'event',
    inputs: [
      { name: 'owner', type: 'address', indexed: true },
      { name: 'spender', type: 'address', indexed: true },
      { name: 'value', type: 'uint256' },
    ],
    name: 'Approval',
  },
  { type: 'event', inputs: [], name: 'ContractLocked' },
  { type: 'event', inputs: [], name: 'ContractUnlocked' },
  {
    type: 'event',
    inputs: [
      { name: 'longOption', type: 'address' },
      { name: 'caller', type: 'address' },
      { name: 'holder', type: 'address' },
      { name: 'amount', type: 'uint256' },
    ],
    name: 'Exercise',
  },
  {
    type: 'event',
    inputs: [{ name: 'version', type: 'uint64' }],
    name: 'Initialized',
  },
  {
    type: 'event',
    inputs: [
      { name: 'longOption', type: 'address' },
      { name: 'holder', type: 'address' },
      { name: 'amount', type: 'uint256' },
    ],
    name: 'Mint',
  },
  {
    type: 'event',
    inputs: [
      { name: 'from', type: 'address', indexed: true },
      { name: 'to', type: 'address', indexed: true },
      { name: 'value', type: 'uint256' },
    ],
    name: 'Transfer',
  },
  { type: 'error', inputs: [], name: 'ContractExpired' },
  { type: 'error', inputs: [], name: 'EuropeanExerciseDisabled' },
  { type: 'error', inputs: [], name: 'ExerciseNotAllowed' },
  { type: 'error', inputs: [], name: 'ExerciseWindowClosed' },
  { type: 'error', inputs: [], name: 'InsufficientBalance' },
  { type: 'error', inputs: [], name: 'InvalidAddress' },
  { type: 'error', inputs: [], name: 'InvalidInitialization' },
  { type: 'error', inputs: [], name: 'InvalidValue' },
  { type: 'error', inputs: [], name: 'LockedContract' },
  { type: 'error', inputs: [], name: 'NotInitializing' },
  { type: 'error', inputs: [], name: 'ReentrancyGuardReentrantCall' },
] as const

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Receipt
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

export const receiptAbi = [
  {
    type: 'constructor',
    inputs: [
      { name: 'name_', type: 'string' },
      { name: 'symbol_', type: 'string' },
    ],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'STRIKE_DECIMALS',
    outputs: [{ type: 'uint8' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'owner', type: 'address' },
      { name: 'spender', type: 'address' },
    ],
    name: 'allowance',
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'spender', type: 'address' },
      { name: 'value', type: 'uint256' },
    ],
    name: 'approve',
    outputs: [{ type: 'bool' }],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [{ name: 'account', type: 'address' }],
    name: 'balanceOf',
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'account', type: 'address' },
      { name: 'amount', type: 'uint256' },
    ],
    name: 'burn',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'collDecimals',
    outputs: [{ type: 'uint8' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'collateral',
    outputs: [{ type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'collateralData',
    outputs: [
      {
        type: 'tuple',
        components: [
          { name: 'address_', type: 'address' },
          { name: 'name', type: 'string' },
          { name: 'symbol', type: 'string' },
          { name: 'decimals', type: 'uint8' },
        ],
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'consDecimals',
    outputs: [{ type: 'uint8' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'consideration',
    outputs: [{ type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'considerationData',
    outputs: [
      {
        type: 'tuple',
        components: [
          { name: 'address_', type: 'address' },
          { name: 'name', type: 'string' },
          { name: 'symbol', type: 'string' },
          { name: 'decimals', type: 'uint8' },
        ],
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'decimals',
    outputs: [{ type: 'uint8' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'account', type: 'address' },
      { name: 'amount', type: 'uint256' },
      { name: 'caller', type: 'address' },
    ],
    name: 'exercise',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'exerciseDeadline',
    outputs: [{ type: 'uint40' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'expirationDate',
    outputs: [{ type: 'uint40' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'factory',
    outputs: [{ type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'collateral_', type: 'address' },
      { name: 'consideration_', type: 'address' },
      { name: 'expirationDate_', type: 'uint40' },
      { name: 'strike_', type: 'uint256' },
      { name: 'isPut_', type: 'bool' },
      { name: 'isEuro_', type: 'bool' },
      { name: 'windowSeconds_', type: 'uint40' },
      { name: 'option_', type: 'address' },
      { name: 'factory_', type: 'address' },
    ],
    name: 'init',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'isEuro',
    outputs: [{ type: 'bool' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'isPut',
    outputs: [{ type: 'bool' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'lock',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'locked',
    outputs: [{ type: 'bool' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'account', type: 'address' },
      { name: 'amount', type: 'uint256' },
    ],
    name: 'mint',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'name',
    outputs: [{ type: 'string' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'option',
    outputs: [{ type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'owner',
    outputs: [{ type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'account', type: 'address' },
      { name: 'amount', type: 'uint256' },
    ],
    name: 'redeem',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'redeem',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [{ name: 'amount', type: 'uint256' }],
    name: 'redeem',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [{ name: 'amount', type: 'uint256' }],
    name: 'redeemConsideration',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'renounceOwnership',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'strike',
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: 'holder', type: 'address' }],
    name: 'sweep',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [{ name: 'holders', type: 'address[]' }],
    name: 'sweep',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'symbol',
    outputs: [{ type: 'string' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: 'consAmount', type: 'uint256' }],
    name: 'toCollateral',
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: 'amount', type: 'uint256' }],
    name: 'toConsideration',
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: 'amount', type: 'uint256' }],
    name: 'toNeededConsideration',
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'totalSupply',
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'to', type: 'address' },
      { name: 'value', type: 'uint256' },
    ],
    name: 'transfer',
    outputs: [{ type: 'bool' }],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'from', type: 'address' },
      { name: 'to', type: 'address' },
      { name: 'value', type: 'uint256' },
    ],
    name: 'transferFrom',
    outputs: [{ type: 'bool' }],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [{ name: 'newOwner', type: 'address' }],
    name: 'transferOwnership',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'unlock',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'event',
    inputs: [
      { name: 'owner', type: 'address', indexed: true },
      { name: 'spender', type: 'address', indexed: true },
      { name: 'value', type: 'uint256' },
    ],
    name: 'Approval',
  },
  {
    type: 'event',
    inputs: [{ name: 'version', type: 'uint64' }],
    name: 'Initialized',
  },
  {
    type: 'event',
    inputs: [
      { name: 'option', type: 'address' },
      { name: 'token', type: 'address' },
      { name: 'holder', type: 'address' },
      { name: 'amount', type: 'uint256' },
    ],
    name: 'Redeemed',
  },
  {
    type: 'event',
    inputs: [
      { name: 'from', type: 'address', indexed: true },
      { name: 'to', type: 'address', indexed: true },
      { name: 'value', type: 'uint256' },
    ],
    name: 'Transfer',
  },
  { type: 'error', inputs: [], name: 'ArithmeticOverflow' },
  { type: 'error', inputs: [], name: 'ContractExpired' },
  { type: 'error', inputs: [], name: 'ContractNotExpired' },
  { type: 'error', inputs: [], name: 'EuropeanExerciseDisabled' },
  { type: 'error', inputs: [], name: 'ExerciseWindowClosed' },
  { type: 'error', inputs: [], name: 'ExerciseWindowOpen' },
  { type: 'error', inputs: [], name: 'FeeOnTransferNotSupported' },
  { type: 'error', inputs: [], name: 'InsufficientBalance' },
  { type: 'error', inputs: [], name: 'InsufficientCollateral' },
  { type: 'error', inputs: [], name: 'InsufficientConsideration' },
  { type: 'error', inputs: [], name: 'InvalidAddress' },
  { type: 'error', inputs: [], name: 'InvalidInitialization' },
  { type: 'error', inputs: [], name: 'InvalidValue' },
  { type: 'error', inputs: [], name: 'LockedContract' },
  { type: 'error', inputs: [], name: 'NotInitializing' },
  { type: 'error', inputs: [], name: 'ReentrancyGuardReentrantCall' },
  {
    type: 'error',
    inputs: [{ name: 'token', type: 'address' }],
    name: 'SafeERC20FailedOperation',
  },
] as const

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// YieldVault
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

export const yieldVaultAbi = [
  {
    type: 'constructor',
    inputs: [
      { name: 'collateral_', type: 'address' },
      { name: 'name_', type: 'string' },
      { name: 'symbol_', type: 'string' },
      { name: 'factory_', type: 'address' },
    ],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [{ name: '', type: 'uint256' }],
    name: 'activeOptions',
    outputs: [{ type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'option', type: 'address' },
      { name: 'spender', type: 'address' },
    ],
    name: 'addOption',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'owner', type: 'address' },
      { name: 'spender', type: 'address' },
    ],
    name: 'allowance',
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'spender', type: 'address' },
      { name: 'value', type: 'uint256' },
    ],
    name: 'approve',
    outputs: [{ type: 'bool' }],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'token', type: 'address' },
      { name: 'spender', type: 'address' },
      { name: 'amount', type: 'uint256' },
    ],
    name: 'approveToken',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'asset',
    outputs: [{ type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: 'account', type: 'address' }],
    name: 'balanceOf',
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'option', type: 'address' },
      { name: 'amount', type: 'uint256' },
    ],
    name: 'burn',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: '', type: 'uint256' },
      { name: 'controller', type: 'address' },
    ],
    name: 'claimableRedeemRequest',
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'cleanupOptions',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [{ name: 'option', type: 'address' }],
    name: 'committed',
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: 'shares', type: 'uint256' }],
    name: 'convertToAssets',
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: 'assets', type: 'uint256' }],
    name: 'convertToShares',
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'decimals',
    outputs: [{ type: 'uint8' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'assets', type: 'uint256' },
      { name: 'receiver', type: 'address' },
    ],
    name: 'deposit',
    outputs: [{ type: 'uint256' }],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [{ name: 'enabled', type: 'bool' }],
    name: 'enableAutoMintBurn',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'target', type: 'address' },
      { name: 'data', type: 'bytes' },
    ],
    name: 'execute',
    outputs: [{ type: 'bytes' }],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'factory',
    outputs: [{ type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: 'controller', type: 'address' }],
    name: 'fulfillRedeem',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [{ name: 'controllers', type: 'address[]' }],
    name: 'fulfillRedeems',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'getVaultStats',
    outputs: [
      { name: 'totalAssets_', type: 'uint256' },
      { name: 'totalShares_', type: 'uint256' },
      { name: 'idle_', type: 'uint256' },
      { name: 'committed_', type: 'uint256' },
      { name: 'utilizationBps_', type: 'uint256' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'idleCollateral',
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'controller', type: 'address' },
      { name: 'operator', type: 'address' },
    ],
    name: 'isOperator',
    outputs: [{ type: 'bool' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'hash', type: 'bytes32' },
      { name: 'signature', type: 'bytes' },
    ],
    name: 'isValidSignature',
    outputs: [{ type: 'bytes4' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: '', type: 'address' }],
    name: 'maxDeposit',
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: '', type: 'address' }],
    name: 'maxMint',
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: 'controller', type: 'address' }],
    name: 'maxRedeem',
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: '', type: 'address' }],
    name: 'maxWithdraw',
    outputs: [{ type: 'uint256' }],
    stateMutability: 'pure',
  },
  {
    type: 'function',
    inputs: [
      { name: 'shares', type: 'uint256' },
      { name: 'receiver', type: 'address' },
    ],
    name: 'mint',
    outputs: [{ type: 'uint256' }],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'name',
    outputs: [{ type: 'string' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'owner',
    outputs: [{ type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'pause',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'paused',
    outputs: [{ type: 'bool' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: '', type: 'uint256' },
      { name: 'controller', type: 'address' },
    ],
    name: 'pendingRedeemRequest',
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: 'assets', type: 'uint256' }],
    name: 'previewDeposit',
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: 'shares', type: 'uint256' }],
    name: 'previewMint',
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: '', type: 'uint256' }],
    name: 'previewRedeem',
    outputs: [{ type: 'uint256' }],
    stateMutability: 'pure',
  },
  {
    type: 'function',
    inputs: [{ name: '', type: 'uint256' }],
    name: 'previewWithdraw',
    outputs: [{ type: 'uint256' }],
    stateMutability: 'pure',
  },
  {
    type: 'function',
    inputs: [
      { name: 'shares', type: 'uint256' },
      { name: 'receiver', type: 'address' },
      { name: 'controller', type: 'address' },
    ],
    name: 'redeem',
    outputs: [{ name: 'assets', type: 'uint256' }],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [{ name: 'option', type: 'address' }],
    name: 'redeemExpired',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [{ name: 'option', type: 'address' }],
    name: 'removeOption',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'renounceOwnership',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'shares', type: 'uint256' },
      { name: 'controller', type: 'address' },
      { name: 'owner', type: 'address' },
    ],
    name: 'requestRedeem',
    outputs: [{ type: 'uint256' }],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'operator', type: 'address' },
      { name: 'approved', type: 'bool' },
    ],
    name: 'setOperator',
    outputs: [{ type: 'bool' }],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'setupFactoryApproval',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'symbol',
    outputs: [{ type: 'string' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'totalAssets',
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'totalCommitted',
    outputs: [{ name: 'total', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'totalSupply',
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'to', type: 'address' },
      { name: 'value', type: 'uint256' },
    ],
    name: 'transfer',
    outputs: [{ type: 'bool' }],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'from', type: 'address' },
      { name: 'to', type: 'address' },
      { name: 'value', type: 'uint256' },
    ],
    name: 'transferFrom',
    outputs: [{ type: 'bool' }],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [{ name: 'newOwner', type: 'address' }],
    name: 'transferOwnership',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'unpause',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'utilizationBps',
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: '', type: 'uint256' },
      { name: '', type: 'address' },
      { name: '', type: 'address' },
    ],
    name: 'withdraw',
    outputs: [{ type: 'uint256' }],
    stateMutability: 'pure',
  },
  {
    type: 'event',
    inputs: [
      { name: 'owner', type: 'address', indexed: true },
      { name: 'spender', type: 'address', indexed: true },
      { name: 'value', type: 'uint256' },
    ],
    name: 'Approval',
  },
  {
    type: 'event',
    inputs: [
      { name: 'sender', type: 'address', indexed: true },
      { name: 'owner', type: 'address', indexed: true },
      { name: 'assets', type: 'uint256' },
      { name: 'shares', type: 'uint256' },
    ],
    name: 'Deposit',
  },
  {
    type: 'event',
    inputs: [
      { name: 'controller', type: 'address', indexed: true },
      { name: 'operator', type: 'address', indexed: true },
      { name: 'approved', type: 'bool' },
    ],
    name: 'OperatorSet',
  },
  {
    type: 'event',
    inputs: [{ name: 'option', type: 'address', indexed: true }],
    name: 'OptionAdded',
  },
  {
    type: 'event',
    inputs: [{ name: 'option', type: 'address', indexed: true }],
    name: 'OptionRemoved',
  },
  {
    type: 'event',
    inputs: [
      { name: 'option', type: 'address', indexed: true },
      { name: 'amount', type: 'uint256' },
    ],
    name: 'OptionsBurned',
  },
  {
    type: 'event',
    inputs: [{ name: 'account', type: 'address' }],
    name: 'Paused',
  },
  {
    type: 'event',
    inputs: [
      { name: 'controller', type: 'address', indexed: true },
      { name: 'owner', type: 'address', indexed: true },
      { name: 'requestId', type: 'uint256', indexed: true },
      { name: 'sender', type: 'address' },
      { name: 'shares', type: 'uint256' },
    ],
    name: 'RedeemRequest',
  },
  {
    type: 'event',
    inputs: [
      { name: 'from', type: 'address', indexed: true },
      { name: 'to', type: 'address', indexed: true },
      { name: 'value', type: 'uint256' },
    ],
    name: 'Transfer',
  },
  {
    type: 'event',
    inputs: [{ name: 'account', type: 'address' }],
    name: 'Unpaused',
  },
  {
    type: 'event',
    inputs: [
      { name: 'sender', type: 'address', indexed: true },
      { name: 'receiver', type: 'address', indexed: true },
      { name: 'owner', type: 'address', indexed: true },
      { name: 'assets', type: 'uint256' },
      { name: 'shares', type: 'uint256' },
    ],
    name: 'Withdraw',
  },
  { type: 'error', inputs: [], name: 'AsyncOnly' },
  { type: 'error', inputs: [], name: 'ECDSAInvalidSignature' },
  {
    type: 'error',
    inputs: [{ name: 'length', type: 'uint256' }],
    name: 'ECDSAInvalidSignatureLength',
  },
  {
    type: 'error',
    inputs: [{ name: 's', type: 'bytes32' }],
    name: 'ECDSAInvalidSignatureS',
  },
  {
    type: 'error',
    inputs: [
      { name: 'receiver', type: 'address' },
      { name: 'assets', type: 'uint256' },
      { name: 'max', type: 'uint256' },
    ],
    name: 'ERC4626ExceededMaxDeposit',
  },
  {
    type: 'error',
    inputs: [
      { name: 'receiver', type: 'address' },
      { name: 'shares', type: 'uint256' },
      { name: 'max', type: 'uint256' },
    ],
    name: 'ERC4626ExceededMaxMint',
  },
  {
    type: 'error',
    inputs: [
      { name: 'owner', type: 'address' },
      { name: 'shares', type: 'uint256' },
      { name: 'max', type: 'uint256' },
    ],
    name: 'ERC4626ExceededMaxRedeem',
  },
  {
    type: 'error',
    inputs: [
      { name: 'owner', type: 'address' },
      { name: 'assets', type: 'uint256' },
      { name: 'max', type: 'uint256' },
    ],
    name: 'ERC4626ExceededMaxWithdraw',
  },
  { type: 'error', inputs: [], name: 'EnforcedPause' },
  { type: 'error', inputs: [], name: 'ExpectedPause' },
  { type: 'error', inputs: [], name: 'InsufficientClaimable' },
  { type: 'error', inputs: [], name: 'InsufficientIdle' },
  { type: 'error', inputs: [], name: 'InvalidAddress' },
  { type: 'error', inputs: [], name: 'ReentrancyGuardReentrantCall' },
  {
    type: 'error',
    inputs: [{ name: 'token', type: 'address' }],
    name: 'SafeERC20FailedOperation',
  },
  { type: 'error', inputs: [], name: 'Unauthorized' },
  { type: 'error', inputs: [], name: 'WithdrawDisabled' },
  { type: 'error', inputs: [], name: 'ZeroAmount' },
] as const

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// React
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link factoryAbi}__
 */
export const useReadFactory = /*#__PURE__*/ createUseReadContract({
  abi: factoryAbi,
})

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link factoryAbi}__ and `functionName` set to `"DEFAULT_EXERCISE_WINDOW"`
 */
export const useReadFactoryDefaultExerciseWindow =
  /*#__PURE__*/ createUseReadContract({
    abi: factoryAbi,
    functionName: 'DEFAULT_EXERCISE_WINDOW',
  })

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link factoryAbi}__ and `functionName` set to `"OPTION_CLONE"`
 */
export const useReadFactoryOptionClone = /*#__PURE__*/ createUseReadContract({
  abi: factoryAbi,
  functionName: 'OPTION_CLONE',
})

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link factoryAbi}__ and `functionName` set to `"RECEIPT_CLONE"`
 */
export const useReadFactoryReceiptClone = /*#__PURE__*/ createUseReadContract({
  abi: factoryAbi,
  functionName: 'RECEIPT_CLONE',
})

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link factoryAbi}__ and `functionName` set to `"allowance"`
 */
export const useReadFactoryAllowance = /*#__PURE__*/ createUseReadContract({
  abi: factoryAbi,
  functionName: 'allowance',
})

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link factoryAbi}__ and `functionName` set to `"approvedOperator"`
 */
export const useReadFactoryApprovedOperator =
  /*#__PURE__*/ createUseReadContract({
    abi: factoryAbi,
    functionName: 'approvedOperator',
  })

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link factoryAbi}__ and `functionName` set to `"autoMintBurn"`
 */
export const useReadFactoryAutoMintBurn = /*#__PURE__*/ createUseReadContract({
  abi: factoryAbi,
  functionName: 'autoMintBurn',
})

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link factoryAbi}__ and `functionName` set to `"blocklist"`
 */
export const useReadFactoryBlocklist = /*#__PURE__*/ createUseReadContract({
  abi: factoryAbi,
  functionName: 'blocklist',
})

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link factoryAbi}__ and `functionName` set to `"exerciseAllowed"`
 */
export const useReadFactoryExerciseAllowed =
  /*#__PURE__*/ createUseReadContract({
    abi: factoryAbi,
    functionName: 'exerciseAllowed',
  })

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link factoryAbi}__ and `functionName` set to `"isBlocked"`
 */
export const useReadFactoryIsBlocked = /*#__PURE__*/ createUseReadContract({
  abi: factoryAbi,
  functionName: 'isBlocked',
})

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link factoryAbi}__ and `functionName` set to `"options"`
 */
export const useReadFactoryOptions = /*#__PURE__*/ createUseReadContract({
  abi: factoryAbi,
  functionName: 'options',
})

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link factoryAbi}__ and `functionName` set to `"owner"`
 */
export const useReadFactoryOwner = /*#__PURE__*/ createUseReadContract({
  abi: factoryAbi,
  functionName: 'owner',
})

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link factoryAbi}__ and `functionName` set to `"receipts"`
 */
export const useReadFactoryReceipts = /*#__PURE__*/ createUseReadContract({
  abi: factoryAbi,
  functionName: 'receipts',
})

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link factoryAbi}__
 */
export const useWriteFactory = /*#__PURE__*/ createUseWriteContract({
  abi: factoryAbi,
})

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link factoryAbi}__ and `functionName` set to `"allowExercise"`
 */
export const useWriteFactoryAllowExercise =
  /*#__PURE__*/ createUseWriteContract({
    abi: factoryAbi,
    functionName: 'allowExercise',
  })

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link factoryAbi}__ and `functionName` set to `"approve"`
 */
export const useWriteFactoryApprove = /*#__PURE__*/ createUseWriteContract({
  abi: factoryAbi,
  functionName: 'approve',
})

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link factoryAbi}__ and `functionName` set to `"approveOperator"`
 */
export const useWriteFactoryApproveOperator =
  /*#__PURE__*/ createUseWriteContract({
    abi: factoryAbi,
    functionName: 'approveOperator',
  })

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link factoryAbi}__ and `functionName` set to `"blockToken"`
 */
export const useWriteFactoryBlockToken = /*#__PURE__*/ createUseWriteContract({
  abi: factoryAbi,
  functionName: 'blockToken',
})

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link factoryAbi}__ and `functionName` set to `"createOption"`
 */
export const useWriteFactoryCreateOption = /*#__PURE__*/ createUseWriteContract(
  { abi: factoryAbi, functionName: 'createOption' },
)

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link factoryAbi}__ and `functionName` set to `"createOptions"`
 */
export const useWriteFactoryCreateOptions =
  /*#__PURE__*/ createUseWriteContract({
    abi: factoryAbi,
    functionName: 'createOptions',
  })

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link factoryAbi}__ and `functionName` set to `"enableAutoMintBurn"`
 */
export const useWriteFactoryEnableAutoMintBurn =
  /*#__PURE__*/ createUseWriteContract({
    abi: factoryAbi,
    functionName: 'enableAutoMintBurn',
  })

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link factoryAbi}__ and `functionName` set to `"renounceOwnership"`
 */
export const useWriteFactoryRenounceOwnership =
  /*#__PURE__*/ createUseWriteContract({
    abi: factoryAbi,
    functionName: 'renounceOwnership',
  })

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link factoryAbi}__ and `functionName` set to `"transferFrom"`
 */
export const useWriteFactoryTransferFrom = /*#__PURE__*/ createUseWriteContract(
  { abi: factoryAbi, functionName: 'transferFrom' },
)

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link factoryAbi}__ and `functionName` set to `"transferOwnership"`
 */
export const useWriteFactoryTransferOwnership =
  /*#__PURE__*/ createUseWriteContract({
    abi: factoryAbi,
    functionName: 'transferOwnership',
  })

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link factoryAbi}__ and `functionName` set to `"unblockToken"`
 */
export const useWriteFactoryUnblockToken = /*#__PURE__*/ createUseWriteContract(
  { abi: factoryAbi, functionName: 'unblockToken' },
)

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link factoryAbi}__
 */
export const useSimulateFactory = /*#__PURE__*/ createUseSimulateContract({
  abi: factoryAbi,
})

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link factoryAbi}__ and `functionName` set to `"allowExercise"`
 */
export const useSimulateFactoryAllowExercise =
  /*#__PURE__*/ createUseSimulateContract({
    abi: factoryAbi,
    functionName: 'allowExercise',
  })

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link factoryAbi}__ and `functionName` set to `"approve"`
 */
export const useSimulateFactoryApprove =
  /*#__PURE__*/ createUseSimulateContract({
    abi: factoryAbi,
    functionName: 'approve',
  })

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link factoryAbi}__ and `functionName` set to `"approveOperator"`
 */
export const useSimulateFactoryApproveOperator =
  /*#__PURE__*/ createUseSimulateContract({
    abi: factoryAbi,
    functionName: 'approveOperator',
  })

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link factoryAbi}__ and `functionName` set to `"blockToken"`
 */
export const useSimulateFactoryBlockToken =
  /*#__PURE__*/ createUseSimulateContract({
    abi: factoryAbi,
    functionName: 'blockToken',
  })

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link factoryAbi}__ and `functionName` set to `"createOption"`
 */
export const useSimulateFactoryCreateOption =
  /*#__PURE__*/ createUseSimulateContract({
    abi: factoryAbi,
    functionName: 'createOption',
  })

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link factoryAbi}__ and `functionName` set to `"createOptions"`
 */
export const useSimulateFactoryCreateOptions =
  /*#__PURE__*/ createUseSimulateContract({
    abi: factoryAbi,
    functionName: 'createOptions',
  })

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link factoryAbi}__ and `functionName` set to `"enableAutoMintBurn"`
 */
export const useSimulateFactoryEnableAutoMintBurn =
  /*#__PURE__*/ createUseSimulateContract({
    abi: factoryAbi,
    functionName: 'enableAutoMintBurn',
  })

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link factoryAbi}__ and `functionName` set to `"renounceOwnership"`
 */
export const useSimulateFactoryRenounceOwnership =
  /*#__PURE__*/ createUseSimulateContract({
    abi: factoryAbi,
    functionName: 'renounceOwnership',
  })

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link factoryAbi}__ and `functionName` set to `"transferFrom"`
 */
export const useSimulateFactoryTransferFrom =
  /*#__PURE__*/ createUseSimulateContract({
    abi: factoryAbi,
    functionName: 'transferFrom',
  })

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link factoryAbi}__ and `functionName` set to `"transferOwnership"`
 */
export const useSimulateFactoryTransferOwnership =
  /*#__PURE__*/ createUseSimulateContract({
    abi: factoryAbi,
    functionName: 'transferOwnership',
  })

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link factoryAbi}__ and `functionName` set to `"unblockToken"`
 */
export const useSimulateFactoryUnblockToken =
  /*#__PURE__*/ createUseSimulateContract({
    abi: factoryAbi,
    functionName: 'unblockToken',
  })

/**
 * Wraps __{@link useWatchContractEvent}__ with `abi` set to __{@link factoryAbi}__
 */
export const useWatchFactoryEvent = /*#__PURE__*/ createUseWatchContractEvent({
  abi: factoryAbi,
})

/**
 * Wraps __{@link useWatchContractEvent}__ with `abi` set to __{@link factoryAbi}__ and `eventName` set to `"Approval"`
 */
export const useWatchFactoryApprovalEvent =
  /*#__PURE__*/ createUseWatchContractEvent({
    abi: factoryAbi,
    eventName: 'Approval',
  })

/**
 * Wraps __{@link useWatchContractEvent}__ with `abi` set to __{@link factoryAbi}__ and `eventName` set to `"AutoMintBurnUpdated"`
 */
export const useWatchFactoryAutoMintBurnUpdatedEvent =
  /*#__PURE__*/ createUseWatchContractEvent({
    abi: factoryAbi,
    eventName: 'AutoMintBurnUpdated',
  })

/**
 * Wraps __{@link useWatchContractEvent}__ with `abi` set to __{@link factoryAbi}__ and `eventName` set to `"ExerciseApproval"`
 */
export const useWatchFactoryExerciseApprovalEvent =
  /*#__PURE__*/ createUseWatchContractEvent({
    abi: factoryAbi,
    eventName: 'ExerciseApproval',
  })

/**
 * Wraps __{@link useWatchContractEvent}__ with `abi` set to __{@link factoryAbi}__ and `eventName` set to `"OperatorApproval"`
 */
export const useWatchFactoryOperatorApprovalEvent =
  /*#__PURE__*/ createUseWatchContractEvent({
    abi: factoryAbi,
    eventName: 'OperatorApproval',
  })

/**
 * Wraps __{@link useWatchContractEvent}__ with `abi` set to __{@link factoryAbi}__ and `eventName` set to `"OptionCreated"`
 */
export const useWatchFactoryOptionCreatedEvent =
  /*#__PURE__*/ createUseWatchContractEvent({
    abi: factoryAbi,
    eventName: 'OptionCreated',
  })

/**
 * Wraps __{@link useWatchContractEvent}__ with `abi` set to __{@link factoryAbi}__ and `eventName` set to `"TokenBlocked"`
 */
export const useWatchFactoryTokenBlockedEvent =
  /*#__PURE__*/ createUseWatchContractEvent({
    abi: factoryAbi,
    eventName: 'TokenBlocked',
  })

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link optionAbi}__
 */
export const useReadOption = /*#__PURE__*/ createUseReadContract({
  abi: optionAbi,
})

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link optionAbi}__ and `functionName` set to `"allowance"`
 */
export const useReadOptionAllowance = /*#__PURE__*/ createUseReadContract({
  abi: optionAbi,
  functionName: 'allowance',
})

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link optionAbi}__ and `functionName` set to `"balanceOf"`
 */
export const useReadOptionBalanceOf = /*#__PURE__*/ createUseReadContract({
  abi: optionAbi,
  functionName: 'balanceOf',
})

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link optionAbi}__ and `functionName` set to `"balancesOf"`
 */
export const useReadOptionBalancesOf = /*#__PURE__*/ createUseReadContract({
  abi: optionAbi,
  functionName: 'balancesOf',
})

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link optionAbi}__ and `functionName` set to `"collateral"`
 */
export const useReadOptionCollateral = /*#__PURE__*/ createUseReadContract({
  abi: optionAbi,
  functionName: 'collateral',
})

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link optionAbi}__ and `functionName` set to `"consideration"`
 */
export const useReadOptionConsideration = /*#__PURE__*/ createUseReadContract({
  abi: optionAbi,
  functionName: 'consideration',
})

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link optionAbi}__ and `functionName` set to `"decimals"`
 */
export const useReadOptionDecimals = /*#__PURE__*/ createUseReadContract({
  abi: optionAbi,
  functionName: 'decimals',
})

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link optionAbi}__ and `functionName` set to `"details"`
 */
export const useReadOptionDetails = /*#__PURE__*/ createUseReadContract({
  abi: optionAbi,
  functionName: 'details',
})

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link optionAbi}__ and `functionName` set to `"exerciseDeadline"`
 */
export const useReadOptionExerciseDeadline =
  /*#__PURE__*/ createUseReadContract({
    abi: optionAbi,
    functionName: 'exerciseDeadline',
  })

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link optionAbi}__ and `functionName` set to `"expirationDate"`
 */
export const useReadOptionExpirationDate = /*#__PURE__*/ createUseReadContract({
  abi: optionAbi,
  functionName: 'expirationDate',
})

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link optionAbi}__ and `functionName` set to `"factory"`
 */
export const useReadOptionFactory = /*#__PURE__*/ createUseReadContract({
  abi: optionAbi,
  functionName: 'factory',
})

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link optionAbi}__ and `functionName` set to `"isEuro"`
 */
export const useReadOptionIsEuro = /*#__PURE__*/ createUseReadContract({
  abi: optionAbi,
  functionName: 'isEuro',
})

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link optionAbi}__ and `functionName` set to `"isPut"`
 */
export const useReadOptionIsPut = /*#__PURE__*/ createUseReadContract({
  abi: optionAbi,
  functionName: 'isPut',
})

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link optionAbi}__ and `functionName` set to `"name"`
 */
export const useReadOptionName = /*#__PURE__*/ createUseReadContract({
  abi: optionAbi,
  functionName: 'name',
})

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link optionAbi}__ and `functionName` set to `"owner"`
 */
export const useReadOptionOwner = /*#__PURE__*/ createUseReadContract({
  abi: optionAbi,
  functionName: 'owner',
})

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link optionAbi}__ and `functionName` set to `"receipt"`
 */
export const useReadOptionReceipt = /*#__PURE__*/ createUseReadContract({
  abi: optionAbi,
  functionName: 'receipt',
})

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link optionAbi}__ and `functionName` set to `"renounceOwnership"`
 */
export const useReadOptionRenounceOwnership =
  /*#__PURE__*/ createUseReadContract({
    abi: optionAbi,
    functionName: 'renounceOwnership',
  })

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link optionAbi}__ and `functionName` set to `"strike"`
 */
export const useReadOptionStrike = /*#__PURE__*/ createUseReadContract({
  abi: optionAbi,
  functionName: 'strike',
})

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link optionAbi}__ and `functionName` set to `"symbol"`
 */
export const useReadOptionSymbol = /*#__PURE__*/ createUseReadContract({
  abi: optionAbi,
  functionName: 'symbol',
})

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link optionAbi}__ and `functionName` set to `"totalSupply"`
 */
export const useReadOptionTotalSupply = /*#__PURE__*/ createUseReadContract({
  abi: optionAbi,
  functionName: 'totalSupply',
})

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link optionAbi}__
 */
export const useWriteOption = /*#__PURE__*/ createUseWriteContract({
  abi: optionAbi,
})

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link optionAbi}__ and `functionName` set to `"approve"`
 */
export const useWriteOptionApprove = /*#__PURE__*/ createUseWriteContract({
  abi: optionAbi,
  functionName: 'approve',
})

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link optionAbi}__ and `functionName` set to `"burn"`
 */
export const useWriteOptionBurn = /*#__PURE__*/ createUseWriteContract({
  abi: optionAbi,
  functionName: 'burn',
})

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link optionAbi}__ and `functionName` set to `"exercise"`
 */
export const useWriteOptionExercise = /*#__PURE__*/ createUseWriteContract({
  abi: optionAbi,
  functionName: 'exercise',
})

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link optionAbi}__ and `functionName` set to `"init"`
 */
export const useWriteOptionInit = /*#__PURE__*/ createUseWriteContract({
  abi: optionAbi,
  functionName: 'init',
})

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link optionAbi}__ and `functionName` set to `"lock"`
 */
export const useWriteOptionLock = /*#__PURE__*/ createUseWriteContract({
  abi: optionAbi,
  functionName: 'lock',
})

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link optionAbi}__ and `functionName` set to `"mint"`
 */
export const useWriteOptionMint = /*#__PURE__*/ createUseWriteContract({
  abi: optionAbi,
  functionName: 'mint',
})

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link optionAbi}__ and `functionName` set to `"transfer"`
 */
export const useWriteOptionTransfer = /*#__PURE__*/ createUseWriteContract({
  abi: optionAbi,
  functionName: 'transfer',
})

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link optionAbi}__ and `functionName` set to `"transferFrom"`
 */
export const useWriteOptionTransferFrom = /*#__PURE__*/ createUseWriteContract({
  abi: optionAbi,
  functionName: 'transferFrom',
})

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link optionAbi}__ and `functionName` set to `"transferOwnership"`
 */
export const useWriteOptionTransferOwnership =
  /*#__PURE__*/ createUseWriteContract({
    abi: optionAbi,
    functionName: 'transferOwnership',
  })

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link optionAbi}__ and `functionName` set to `"unlock"`
 */
export const useWriteOptionUnlock = /*#__PURE__*/ createUseWriteContract({
  abi: optionAbi,
  functionName: 'unlock',
})

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link optionAbi}__
 */
export const useSimulateOption = /*#__PURE__*/ createUseSimulateContract({
  abi: optionAbi,
})

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link optionAbi}__ and `functionName` set to `"approve"`
 */
export const useSimulateOptionApprove = /*#__PURE__*/ createUseSimulateContract(
  { abi: optionAbi, functionName: 'approve' },
)

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link optionAbi}__ and `functionName` set to `"burn"`
 */
export const useSimulateOptionBurn = /*#__PURE__*/ createUseSimulateContract({
  abi: optionAbi,
  functionName: 'burn',
})

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link optionAbi}__ and `functionName` set to `"exercise"`
 */
export const useSimulateOptionExercise =
  /*#__PURE__*/ createUseSimulateContract({
    abi: optionAbi,
    functionName: 'exercise',
  })

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link optionAbi}__ and `functionName` set to `"init"`
 */
export const useSimulateOptionInit = /*#__PURE__*/ createUseSimulateContract({
  abi: optionAbi,
  functionName: 'init',
})

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link optionAbi}__ and `functionName` set to `"lock"`
 */
export const useSimulateOptionLock = /*#__PURE__*/ createUseSimulateContract({
  abi: optionAbi,
  functionName: 'lock',
})

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link optionAbi}__ and `functionName` set to `"mint"`
 */
export const useSimulateOptionMint = /*#__PURE__*/ createUseSimulateContract({
  abi: optionAbi,
  functionName: 'mint',
})

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link optionAbi}__ and `functionName` set to `"transfer"`
 */
export const useSimulateOptionTransfer =
  /*#__PURE__*/ createUseSimulateContract({
    abi: optionAbi,
    functionName: 'transfer',
  })

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link optionAbi}__ and `functionName` set to `"transferFrom"`
 */
export const useSimulateOptionTransferFrom =
  /*#__PURE__*/ createUseSimulateContract({
    abi: optionAbi,
    functionName: 'transferFrom',
  })

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link optionAbi}__ and `functionName` set to `"transferOwnership"`
 */
export const useSimulateOptionTransferOwnership =
  /*#__PURE__*/ createUseSimulateContract({
    abi: optionAbi,
    functionName: 'transferOwnership',
  })

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link optionAbi}__ and `functionName` set to `"unlock"`
 */
export const useSimulateOptionUnlock = /*#__PURE__*/ createUseSimulateContract({
  abi: optionAbi,
  functionName: 'unlock',
})

/**
 * Wraps __{@link useWatchContractEvent}__ with `abi` set to __{@link optionAbi}__
 */
export const useWatchOptionEvent = /*#__PURE__*/ createUseWatchContractEvent({
  abi: optionAbi,
})

/**
 * Wraps __{@link useWatchContractEvent}__ with `abi` set to __{@link optionAbi}__ and `eventName` set to `"Approval"`
 */
export const useWatchOptionApprovalEvent =
  /*#__PURE__*/ createUseWatchContractEvent({
    abi: optionAbi,
    eventName: 'Approval',
  })

/**
 * Wraps __{@link useWatchContractEvent}__ with `abi` set to __{@link optionAbi}__ and `eventName` set to `"ContractLocked"`
 */
export const useWatchOptionContractLockedEvent =
  /*#__PURE__*/ createUseWatchContractEvent({
    abi: optionAbi,
    eventName: 'ContractLocked',
  })

/**
 * Wraps __{@link useWatchContractEvent}__ with `abi` set to __{@link optionAbi}__ and `eventName` set to `"ContractUnlocked"`
 */
export const useWatchOptionContractUnlockedEvent =
  /*#__PURE__*/ createUseWatchContractEvent({
    abi: optionAbi,
    eventName: 'ContractUnlocked',
  })

/**
 * Wraps __{@link useWatchContractEvent}__ with `abi` set to __{@link optionAbi}__ and `eventName` set to `"Exercise"`
 */
export const useWatchOptionExerciseEvent =
  /*#__PURE__*/ createUseWatchContractEvent({
    abi: optionAbi,
    eventName: 'Exercise',
  })

/**
 * Wraps __{@link useWatchContractEvent}__ with `abi` set to __{@link optionAbi}__ and `eventName` set to `"Initialized"`
 */
export const useWatchOptionInitializedEvent =
  /*#__PURE__*/ createUseWatchContractEvent({
    abi: optionAbi,
    eventName: 'Initialized',
  })

/**
 * Wraps __{@link useWatchContractEvent}__ with `abi` set to __{@link optionAbi}__ and `eventName` set to `"Mint"`
 */
export const useWatchOptionMintEvent =
  /*#__PURE__*/ createUseWatchContractEvent({
    abi: optionAbi,
    eventName: 'Mint',
  })

/**
 * Wraps __{@link useWatchContractEvent}__ with `abi` set to __{@link optionAbi}__ and `eventName` set to `"Transfer"`
 */
export const useWatchOptionTransferEvent =
  /*#__PURE__*/ createUseWatchContractEvent({
    abi: optionAbi,
    eventName: 'Transfer',
  })

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link receiptAbi}__
 */
export const useReadReceipt = /*#__PURE__*/ createUseReadContract({
  abi: receiptAbi,
})

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link receiptAbi}__ and `functionName` set to `"STRIKE_DECIMALS"`
 */
export const useReadReceiptStrikeDecimals = /*#__PURE__*/ createUseReadContract(
  { abi: receiptAbi, functionName: 'STRIKE_DECIMALS' },
)

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link receiptAbi}__ and `functionName` set to `"allowance"`
 */
export const useReadReceiptAllowance = /*#__PURE__*/ createUseReadContract({
  abi: receiptAbi,
  functionName: 'allowance',
})

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link receiptAbi}__ and `functionName` set to `"balanceOf"`
 */
export const useReadReceiptBalanceOf = /*#__PURE__*/ createUseReadContract({
  abi: receiptAbi,
  functionName: 'balanceOf',
})

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link receiptAbi}__ and `functionName` set to `"collDecimals"`
 */
export const useReadReceiptCollDecimals = /*#__PURE__*/ createUseReadContract({
  abi: receiptAbi,
  functionName: 'collDecimals',
})

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link receiptAbi}__ and `functionName` set to `"collateral"`
 */
export const useReadReceiptCollateral = /*#__PURE__*/ createUseReadContract({
  abi: receiptAbi,
  functionName: 'collateral',
})

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link receiptAbi}__ and `functionName` set to `"collateralData"`
 */
export const useReadReceiptCollateralData = /*#__PURE__*/ createUseReadContract(
  { abi: receiptAbi, functionName: 'collateralData' },
)

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link receiptAbi}__ and `functionName` set to `"consDecimals"`
 */
export const useReadReceiptConsDecimals = /*#__PURE__*/ createUseReadContract({
  abi: receiptAbi,
  functionName: 'consDecimals',
})

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link receiptAbi}__ and `functionName` set to `"consideration"`
 */
export const useReadReceiptConsideration = /*#__PURE__*/ createUseReadContract({
  abi: receiptAbi,
  functionName: 'consideration',
})

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link receiptAbi}__ and `functionName` set to `"considerationData"`
 */
export const useReadReceiptConsiderationData =
  /*#__PURE__*/ createUseReadContract({
    abi: receiptAbi,
    functionName: 'considerationData',
  })

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link receiptAbi}__ and `functionName` set to `"decimals"`
 */
export const useReadReceiptDecimals = /*#__PURE__*/ createUseReadContract({
  abi: receiptAbi,
  functionName: 'decimals',
})

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link receiptAbi}__ and `functionName` set to `"exerciseDeadline"`
 */
export const useReadReceiptExerciseDeadline =
  /*#__PURE__*/ createUseReadContract({
    abi: receiptAbi,
    functionName: 'exerciseDeadline',
  })

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link receiptAbi}__ and `functionName` set to `"expirationDate"`
 */
export const useReadReceiptExpirationDate = /*#__PURE__*/ createUseReadContract(
  { abi: receiptAbi, functionName: 'expirationDate' },
)

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link receiptAbi}__ and `functionName` set to `"factory"`
 */
export const useReadReceiptFactory = /*#__PURE__*/ createUseReadContract({
  abi: receiptAbi,
  functionName: 'factory',
})

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link receiptAbi}__ and `functionName` set to `"isEuro"`
 */
export const useReadReceiptIsEuro = /*#__PURE__*/ createUseReadContract({
  abi: receiptAbi,
  functionName: 'isEuro',
})

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link receiptAbi}__ and `functionName` set to `"isPut"`
 */
export const useReadReceiptIsPut = /*#__PURE__*/ createUseReadContract({
  abi: receiptAbi,
  functionName: 'isPut',
})

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link receiptAbi}__ and `functionName` set to `"locked"`
 */
export const useReadReceiptLocked = /*#__PURE__*/ createUseReadContract({
  abi: receiptAbi,
  functionName: 'locked',
})

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link receiptAbi}__ and `functionName` set to `"name"`
 */
export const useReadReceiptName = /*#__PURE__*/ createUseReadContract({
  abi: receiptAbi,
  functionName: 'name',
})

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link receiptAbi}__ and `functionName` set to `"option"`
 */
export const useReadReceiptOption = /*#__PURE__*/ createUseReadContract({
  abi: receiptAbi,
  functionName: 'option',
})

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link receiptAbi}__ and `functionName` set to `"owner"`
 */
export const useReadReceiptOwner = /*#__PURE__*/ createUseReadContract({
  abi: receiptAbi,
  functionName: 'owner',
})

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link receiptAbi}__ and `functionName` set to `"strike"`
 */
export const useReadReceiptStrike = /*#__PURE__*/ createUseReadContract({
  abi: receiptAbi,
  functionName: 'strike',
})

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link receiptAbi}__ and `functionName` set to `"symbol"`
 */
export const useReadReceiptSymbol = /*#__PURE__*/ createUseReadContract({
  abi: receiptAbi,
  functionName: 'symbol',
})

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link receiptAbi}__ and `functionName` set to `"toCollateral"`
 */
export const useReadReceiptToCollateral = /*#__PURE__*/ createUseReadContract({
  abi: receiptAbi,
  functionName: 'toCollateral',
})

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link receiptAbi}__ and `functionName` set to `"toConsideration"`
 */
export const useReadReceiptToConsideration =
  /*#__PURE__*/ createUseReadContract({
    abi: receiptAbi,
    functionName: 'toConsideration',
  })

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link receiptAbi}__ and `functionName` set to `"toNeededConsideration"`
 */
export const useReadReceiptToNeededConsideration =
  /*#__PURE__*/ createUseReadContract({
    abi: receiptAbi,
    functionName: 'toNeededConsideration',
  })

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link receiptAbi}__ and `functionName` set to `"totalSupply"`
 */
export const useReadReceiptTotalSupply = /*#__PURE__*/ createUseReadContract({
  abi: receiptAbi,
  functionName: 'totalSupply',
})

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link receiptAbi}__
 */
export const useWriteReceipt = /*#__PURE__*/ createUseWriteContract({
  abi: receiptAbi,
})

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link receiptAbi}__ and `functionName` set to `"approve"`
 */
export const useWriteReceiptApprove = /*#__PURE__*/ createUseWriteContract({
  abi: receiptAbi,
  functionName: 'approve',
})

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link receiptAbi}__ and `functionName` set to `"burn"`
 */
export const useWriteReceiptBurn = /*#__PURE__*/ createUseWriteContract({
  abi: receiptAbi,
  functionName: 'burn',
})

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link receiptAbi}__ and `functionName` set to `"exercise"`
 */
export const useWriteReceiptExercise = /*#__PURE__*/ createUseWriteContract({
  abi: receiptAbi,
  functionName: 'exercise',
})

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link receiptAbi}__ and `functionName` set to `"init"`
 */
export const useWriteReceiptInit = /*#__PURE__*/ createUseWriteContract({
  abi: receiptAbi,
  functionName: 'init',
})

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link receiptAbi}__ and `functionName` set to `"lock"`
 */
export const useWriteReceiptLock = /*#__PURE__*/ createUseWriteContract({
  abi: receiptAbi,
  functionName: 'lock',
})

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link receiptAbi}__ and `functionName` set to `"mint"`
 */
export const useWriteReceiptMint = /*#__PURE__*/ createUseWriteContract({
  abi: receiptAbi,
  functionName: 'mint',
})

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link receiptAbi}__ and `functionName` set to `"redeem"`
 */
export const useWriteReceiptRedeem = /*#__PURE__*/ createUseWriteContract({
  abi: receiptAbi,
  functionName: 'redeem',
})

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link receiptAbi}__ and `functionName` set to `"redeemConsideration"`
 */
export const useWriteReceiptRedeemConsideration =
  /*#__PURE__*/ createUseWriteContract({
    abi: receiptAbi,
    functionName: 'redeemConsideration',
  })

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link receiptAbi}__ and `functionName` set to `"renounceOwnership"`
 */
export const useWriteReceiptRenounceOwnership =
  /*#__PURE__*/ createUseWriteContract({
    abi: receiptAbi,
    functionName: 'renounceOwnership',
  })

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link receiptAbi}__ and `functionName` set to `"sweep"`
 */
export const useWriteReceiptSweep = /*#__PURE__*/ createUseWriteContract({
  abi: receiptAbi,
  functionName: 'sweep',
})

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link receiptAbi}__ and `functionName` set to `"transfer"`
 */
export const useWriteReceiptTransfer = /*#__PURE__*/ createUseWriteContract({
  abi: receiptAbi,
  functionName: 'transfer',
})

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link receiptAbi}__ and `functionName` set to `"transferFrom"`
 */
export const useWriteReceiptTransferFrom = /*#__PURE__*/ createUseWriteContract(
  { abi: receiptAbi, functionName: 'transferFrom' },
)

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link receiptAbi}__ and `functionName` set to `"transferOwnership"`
 */
export const useWriteReceiptTransferOwnership =
  /*#__PURE__*/ createUseWriteContract({
    abi: receiptAbi,
    functionName: 'transferOwnership',
  })

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link receiptAbi}__ and `functionName` set to `"unlock"`
 */
export const useWriteReceiptUnlock = /*#__PURE__*/ createUseWriteContract({
  abi: receiptAbi,
  functionName: 'unlock',
})

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link receiptAbi}__
 */
export const useSimulateReceipt = /*#__PURE__*/ createUseSimulateContract({
  abi: receiptAbi,
})

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link receiptAbi}__ and `functionName` set to `"approve"`
 */
export const useSimulateReceiptApprove =
  /*#__PURE__*/ createUseSimulateContract({
    abi: receiptAbi,
    functionName: 'approve',
  })

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link receiptAbi}__ and `functionName` set to `"burn"`
 */
export const useSimulateReceiptBurn = /*#__PURE__*/ createUseSimulateContract({
  abi: receiptAbi,
  functionName: 'burn',
})

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link receiptAbi}__ and `functionName` set to `"exercise"`
 */
export const useSimulateReceiptExercise =
  /*#__PURE__*/ createUseSimulateContract({
    abi: receiptAbi,
    functionName: 'exercise',
  })

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link receiptAbi}__ and `functionName` set to `"init"`
 */
export const useSimulateReceiptInit = /*#__PURE__*/ createUseSimulateContract({
  abi: receiptAbi,
  functionName: 'init',
})

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link receiptAbi}__ and `functionName` set to `"lock"`
 */
export const useSimulateReceiptLock = /*#__PURE__*/ createUseSimulateContract({
  abi: receiptAbi,
  functionName: 'lock',
})

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link receiptAbi}__ and `functionName` set to `"mint"`
 */
export const useSimulateReceiptMint = /*#__PURE__*/ createUseSimulateContract({
  abi: receiptAbi,
  functionName: 'mint',
})

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link receiptAbi}__ and `functionName` set to `"redeem"`
 */
export const useSimulateReceiptRedeem = /*#__PURE__*/ createUseSimulateContract(
  { abi: receiptAbi, functionName: 'redeem' },
)

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link receiptAbi}__ and `functionName` set to `"redeemConsideration"`
 */
export const useSimulateReceiptRedeemConsideration =
  /*#__PURE__*/ createUseSimulateContract({
    abi: receiptAbi,
    functionName: 'redeemConsideration',
  })

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link receiptAbi}__ and `functionName` set to `"renounceOwnership"`
 */
export const useSimulateReceiptRenounceOwnership =
  /*#__PURE__*/ createUseSimulateContract({
    abi: receiptAbi,
    functionName: 'renounceOwnership',
  })

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link receiptAbi}__ and `functionName` set to `"sweep"`
 */
export const useSimulateReceiptSweep = /*#__PURE__*/ createUseSimulateContract({
  abi: receiptAbi,
  functionName: 'sweep',
})

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link receiptAbi}__ and `functionName` set to `"transfer"`
 */
export const useSimulateReceiptTransfer =
  /*#__PURE__*/ createUseSimulateContract({
    abi: receiptAbi,
    functionName: 'transfer',
  })

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link receiptAbi}__ and `functionName` set to `"transferFrom"`
 */
export const useSimulateReceiptTransferFrom =
  /*#__PURE__*/ createUseSimulateContract({
    abi: receiptAbi,
    functionName: 'transferFrom',
  })

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link receiptAbi}__ and `functionName` set to `"transferOwnership"`
 */
export const useSimulateReceiptTransferOwnership =
  /*#__PURE__*/ createUseSimulateContract({
    abi: receiptAbi,
    functionName: 'transferOwnership',
  })

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link receiptAbi}__ and `functionName` set to `"unlock"`
 */
export const useSimulateReceiptUnlock = /*#__PURE__*/ createUseSimulateContract(
  { abi: receiptAbi, functionName: 'unlock' },
)

/**
 * Wraps __{@link useWatchContractEvent}__ with `abi` set to __{@link receiptAbi}__
 */
export const useWatchReceiptEvent = /*#__PURE__*/ createUseWatchContractEvent({
  abi: receiptAbi,
})

/**
 * Wraps __{@link useWatchContractEvent}__ with `abi` set to __{@link receiptAbi}__ and `eventName` set to `"Approval"`
 */
export const useWatchReceiptApprovalEvent =
  /*#__PURE__*/ createUseWatchContractEvent({
    abi: receiptAbi,
    eventName: 'Approval',
  })

/**
 * Wraps __{@link useWatchContractEvent}__ with `abi` set to __{@link receiptAbi}__ and `eventName` set to `"Initialized"`
 */
export const useWatchReceiptInitializedEvent =
  /*#__PURE__*/ createUseWatchContractEvent({
    abi: receiptAbi,
    eventName: 'Initialized',
  })

/**
 * Wraps __{@link useWatchContractEvent}__ with `abi` set to __{@link receiptAbi}__ and `eventName` set to `"Redeemed"`
 */
export const useWatchReceiptRedeemedEvent =
  /*#__PURE__*/ createUseWatchContractEvent({
    abi: receiptAbi,
    eventName: 'Redeemed',
  })

/**
 * Wraps __{@link useWatchContractEvent}__ with `abi` set to __{@link receiptAbi}__ and `eventName` set to `"Transfer"`
 */
export const useWatchReceiptTransferEvent =
  /*#__PURE__*/ createUseWatchContractEvent({
    abi: receiptAbi,
    eventName: 'Transfer',
  })

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link yieldVaultAbi}__
 */
export const useReadYieldVault = /*#__PURE__*/ createUseReadContract({
  abi: yieldVaultAbi,
})

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"activeOptions"`
 */
export const useReadYieldVaultActiveOptions =
  /*#__PURE__*/ createUseReadContract({
    abi: yieldVaultAbi,
    functionName: 'activeOptions',
  })

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"allowance"`
 */
export const useReadYieldVaultAllowance = /*#__PURE__*/ createUseReadContract({
  abi: yieldVaultAbi,
  functionName: 'allowance',
})

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"asset"`
 */
export const useReadYieldVaultAsset = /*#__PURE__*/ createUseReadContract({
  abi: yieldVaultAbi,
  functionName: 'asset',
})

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"balanceOf"`
 */
export const useReadYieldVaultBalanceOf = /*#__PURE__*/ createUseReadContract({
  abi: yieldVaultAbi,
  functionName: 'balanceOf',
})

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"claimableRedeemRequest"`
 */
export const useReadYieldVaultClaimableRedeemRequest =
  /*#__PURE__*/ createUseReadContract({
    abi: yieldVaultAbi,
    functionName: 'claimableRedeemRequest',
  })

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"committed"`
 */
export const useReadYieldVaultCommitted = /*#__PURE__*/ createUseReadContract({
  abi: yieldVaultAbi,
  functionName: 'committed',
})

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"convertToAssets"`
 */
export const useReadYieldVaultConvertToAssets =
  /*#__PURE__*/ createUseReadContract({
    abi: yieldVaultAbi,
    functionName: 'convertToAssets',
  })

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"convertToShares"`
 */
export const useReadYieldVaultConvertToShares =
  /*#__PURE__*/ createUseReadContract({
    abi: yieldVaultAbi,
    functionName: 'convertToShares',
  })

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"decimals"`
 */
export const useReadYieldVaultDecimals = /*#__PURE__*/ createUseReadContract({
  abi: yieldVaultAbi,
  functionName: 'decimals',
})

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"factory"`
 */
export const useReadYieldVaultFactory = /*#__PURE__*/ createUseReadContract({
  abi: yieldVaultAbi,
  functionName: 'factory',
})

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"getVaultStats"`
 */
export const useReadYieldVaultGetVaultStats =
  /*#__PURE__*/ createUseReadContract({
    abi: yieldVaultAbi,
    functionName: 'getVaultStats',
  })

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"idleCollateral"`
 */
export const useReadYieldVaultIdleCollateral =
  /*#__PURE__*/ createUseReadContract({
    abi: yieldVaultAbi,
    functionName: 'idleCollateral',
  })

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"isOperator"`
 */
export const useReadYieldVaultIsOperator = /*#__PURE__*/ createUseReadContract({
  abi: yieldVaultAbi,
  functionName: 'isOperator',
})

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"isValidSignature"`
 */
export const useReadYieldVaultIsValidSignature =
  /*#__PURE__*/ createUseReadContract({
    abi: yieldVaultAbi,
    functionName: 'isValidSignature',
  })

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"maxDeposit"`
 */
export const useReadYieldVaultMaxDeposit = /*#__PURE__*/ createUseReadContract({
  abi: yieldVaultAbi,
  functionName: 'maxDeposit',
})

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"maxMint"`
 */
export const useReadYieldVaultMaxMint = /*#__PURE__*/ createUseReadContract({
  abi: yieldVaultAbi,
  functionName: 'maxMint',
})

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"maxRedeem"`
 */
export const useReadYieldVaultMaxRedeem = /*#__PURE__*/ createUseReadContract({
  abi: yieldVaultAbi,
  functionName: 'maxRedeem',
})

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"maxWithdraw"`
 */
export const useReadYieldVaultMaxWithdraw = /*#__PURE__*/ createUseReadContract(
  { abi: yieldVaultAbi, functionName: 'maxWithdraw' },
)

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"name"`
 */
export const useReadYieldVaultName = /*#__PURE__*/ createUseReadContract({
  abi: yieldVaultAbi,
  functionName: 'name',
})

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"owner"`
 */
export const useReadYieldVaultOwner = /*#__PURE__*/ createUseReadContract({
  abi: yieldVaultAbi,
  functionName: 'owner',
})

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"paused"`
 */
export const useReadYieldVaultPaused = /*#__PURE__*/ createUseReadContract({
  abi: yieldVaultAbi,
  functionName: 'paused',
})

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"pendingRedeemRequest"`
 */
export const useReadYieldVaultPendingRedeemRequest =
  /*#__PURE__*/ createUseReadContract({
    abi: yieldVaultAbi,
    functionName: 'pendingRedeemRequest',
  })

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"previewDeposit"`
 */
export const useReadYieldVaultPreviewDeposit =
  /*#__PURE__*/ createUseReadContract({
    abi: yieldVaultAbi,
    functionName: 'previewDeposit',
  })

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"previewMint"`
 */
export const useReadYieldVaultPreviewMint = /*#__PURE__*/ createUseReadContract(
  { abi: yieldVaultAbi, functionName: 'previewMint' },
)

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"previewRedeem"`
 */
export const useReadYieldVaultPreviewRedeem =
  /*#__PURE__*/ createUseReadContract({
    abi: yieldVaultAbi,
    functionName: 'previewRedeem',
  })

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"previewWithdraw"`
 */
export const useReadYieldVaultPreviewWithdraw =
  /*#__PURE__*/ createUseReadContract({
    abi: yieldVaultAbi,
    functionName: 'previewWithdraw',
  })

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"symbol"`
 */
export const useReadYieldVaultSymbol = /*#__PURE__*/ createUseReadContract({
  abi: yieldVaultAbi,
  functionName: 'symbol',
})

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"totalAssets"`
 */
export const useReadYieldVaultTotalAssets = /*#__PURE__*/ createUseReadContract(
  { abi: yieldVaultAbi, functionName: 'totalAssets' },
)

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"totalCommitted"`
 */
export const useReadYieldVaultTotalCommitted =
  /*#__PURE__*/ createUseReadContract({
    abi: yieldVaultAbi,
    functionName: 'totalCommitted',
  })

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"totalSupply"`
 */
export const useReadYieldVaultTotalSupply = /*#__PURE__*/ createUseReadContract(
  { abi: yieldVaultAbi, functionName: 'totalSupply' },
)

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"utilizationBps"`
 */
export const useReadYieldVaultUtilizationBps =
  /*#__PURE__*/ createUseReadContract({
    abi: yieldVaultAbi,
    functionName: 'utilizationBps',
  })

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"withdraw"`
 */
export const useReadYieldVaultWithdraw = /*#__PURE__*/ createUseReadContract({
  abi: yieldVaultAbi,
  functionName: 'withdraw',
})

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link yieldVaultAbi}__
 */
export const useWriteYieldVault = /*#__PURE__*/ createUseWriteContract({
  abi: yieldVaultAbi,
})

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"addOption"`
 */
export const useWriteYieldVaultAddOption = /*#__PURE__*/ createUseWriteContract(
  { abi: yieldVaultAbi, functionName: 'addOption' },
)

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"approve"`
 */
export const useWriteYieldVaultApprove = /*#__PURE__*/ createUseWriteContract({
  abi: yieldVaultAbi,
  functionName: 'approve',
})

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"approveToken"`
 */
export const useWriteYieldVaultApproveToken =
  /*#__PURE__*/ createUseWriteContract({
    abi: yieldVaultAbi,
    functionName: 'approveToken',
  })

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"burn"`
 */
export const useWriteYieldVaultBurn = /*#__PURE__*/ createUseWriteContract({
  abi: yieldVaultAbi,
  functionName: 'burn',
})

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"cleanupOptions"`
 */
export const useWriteYieldVaultCleanupOptions =
  /*#__PURE__*/ createUseWriteContract({
    abi: yieldVaultAbi,
    functionName: 'cleanupOptions',
  })

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"deposit"`
 */
export const useWriteYieldVaultDeposit = /*#__PURE__*/ createUseWriteContract({
  abi: yieldVaultAbi,
  functionName: 'deposit',
})

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"enableAutoMintBurn"`
 */
export const useWriteYieldVaultEnableAutoMintBurn =
  /*#__PURE__*/ createUseWriteContract({
    abi: yieldVaultAbi,
    functionName: 'enableAutoMintBurn',
  })

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"execute"`
 */
export const useWriteYieldVaultExecute = /*#__PURE__*/ createUseWriteContract({
  abi: yieldVaultAbi,
  functionName: 'execute',
})

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"fulfillRedeem"`
 */
export const useWriteYieldVaultFulfillRedeem =
  /*#__PURE__*/ createUseWriteContract({
    abi: yieldVaultAbi,
    functionName: 'fulfillRedeem',
  })

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"fulfillRedeems"`
 */
export const useWriteYieldVaultFulfillRedeems =
  /*#__PURE__*/ createUseWriteContract({
    abi: yieldVaultAbi,
    functionName: 'fulfillRedeems',
  })

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"mint"`
 */
export const useWriteYieldVaultMint = /*#__PURE__*/ createUseWriteContract({
  abi: yieldVaultAbi,
  functionName: 'mint',
})

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"pause"`
 */
export const useWriteYieldVaultPause = /*#__PURE__*/ createUseWriteContract({
  abi: yieldVaultAbi,
  functionName: 'pause',
})

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"redeem"`
 */
export const useWriteYieldVaultRedeem = /*#__PURE__*/ createUseWriteContract({
  abi: yieldVaultAbi,
  functionName: 'redeem',
})

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"redeemExpired"`
 */
export const useWriteYieldVaultRedeemExpired =
  /*#__PURE__*/ createUseWriteContract({
    abi: yieldVaultAbi,
    functionName: 'redeemExpired',
  })

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"removeOption"`
 */
export const useWriteYieldVaultRemoveOption =
  /*#__PURE__*/ createUseWriteContract({
    abi: yieldVaultAbi,
    functionName: 'removeOption',
  })

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"renounceOwnership"`
 */
export const useWriteYieldVaultRenounceOwnership =
  /*#__PURE__*/ createUseWriteContract({
    abi: yieldVaultAbi,
    functionName: 'renounceOwnership',
  })

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"requestRedeem"`
 */
export const useWriteYieldVaultRequestRedeem =
  /*#__PURE__*/ createUseWriteContract({
    abi: yieldVaultAbi,
    functionName: 'requestRedeem',
  })

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"setOperator"`
 */
export const useWriteYieldVaultSetOperator =
  /*#__PURE__*/ createUseWriteContract({
    abi: yieldVaultAbi,
    functionName: 'setOperator',
  })

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"setupFactoryApproval"`
 */
export const useWriteYieldVaultSetupFactoryApproval =
  /*#__PURE__*/ createUseWriteContract({
    abi: yieldVaultAbi,
    functionName: 'setupFactoryApproval',
  })

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"transfer"`
 */
export const useWriteYieldVaultTransfer = /*#__PURE__*/ createUseWriteContract({
  abi: yieldVaultAbi,
  functionName: 'transfer',
})

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"transferFrom"`
 */
export const useWriteYieldVaultTransferFrom =
  /*#__PURE__*/ createUseWriteContract({
    abi: yieldVaultAbi,
    functionName: 'transferFrom',
  })

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"transferOwnership"`
 */
export const useWriteYieldVaultTransferOwnership =
  /*#__PURE__*/ createUseWriteContract({
    abi: yieldVaultAbi,
    functionName: 'transferOwnership',
  })

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"unpause"`
 */
export const useWriteYieldVaultUnpause = /*#__PURE__*/ createUseWriteContract({
  abi: yieldVaultAbi,
  functionName: 'unpause',
})

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link yieldVaultAbi}__
 */
export const useSimulateYieldVault = /*#__PURE__*/ createUseSimulateContract({
  abi: yieldVaultAbi,
})

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"addOption"`
 */
export const useSimulateYieldVaultAddOption =
  /*#__PURE__*/ createUseSimulateContract({
    abi: yieldVaultAbi,
    functionName: 'addOption',
  })

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"approve"`
 */
export const useSimulateYieldVaultApprove =
  /*#__PURE__*/ createUseSimulateContract({
    abi: yieldVaultAbi,
    functionName: 'approve',
  })

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"approveToken"`
 */
export const useSimulateYieldVaultApproveToken =
  /*#__PURE__*/ createUseSimulateContract({
    abi: yieldVaultAbi,
    functionName: 'approveToken',
  })

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"burn"`
 */
export const useSimulateYieldVaultBurn =
  /*#__PURE__*/ createUseSimulateContract({
    abi: yieldVaultAbi,
    functionName: 'burn',
  })

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"cleanupOptions"`
 */
export const useSimulateYieldVaultCleanupOptions =
  /*#__PURE__*/ createUseSimulateContract({
    abi: yieldVaultAbi,
    functionName: 'cleanupOptions',
  })

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"deposit"`
 */
export const useSimulateYieldVaultDeposit =
  /*#__PURE__*/ createUseSimulateContract({
    abi: yieldVaultAbi,
    functionName: 'deposit',
  })

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"enableAutoMintBurn"`
 */
export const useSimulateYieldVaultEnableAutoMintBurn =
  /*#__PURE__*/ createUseSimulateContract({
    abi: yieldVaultAbi,
    functionName: 'enableAutoMintBurn',
  })

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"execute"`
 */
export const useSimulateYieldVaultExecute =
  /*#__PURE__*/ createUseSimulateContract({
    abi: yieldVaultAbi,
    functionName: 'execute',
  })

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"fulfillRedeem"`
 */
export const useSimulateYieldVaultFulfillRedeem =
  /*#__PURE__*/ createUseSimulateContract({
    abi: yieldVaultAbi,
    functionName: 'fulfillRedeem',
  })

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"fulfillRedeems"`
 */
export const useSimulateYieldVaultFulfillRedeems =
  /*#__PURE__*/ createUseSimulateContract({
    abi: yieldVaultAbi,
    functionName: 'fulfillRedeems',
  })

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"mint"`
 */
export const useSimulateYieldVaultMint =
  /*#__PURE__*/ createUseSimulateContract({
    abi: yieldVaultAbi,
    functionName: 'mint',
  })

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"pause"`
 */
export const useSimulateYieldVaultPause =
  /*#__PURE__*/ createUseSimulateContract({
    abi: yieldVaultAbi,
    functionName: 'pause',
  })

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"redeem"`
 */
export const useSimulateYieldVaultRedeem =
  /*#__PURE__*/ createUseSimulateContract({
    abi: yieldVaultAbi,
    functionName: 'redeem',
  })

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"redeemExpired"`
 */
export const useSimulateYieldVaultRedeemExpired =
  /*#__PURE__*/ createUseSimulateContract({
    abi: yieldVaultAbi,
    functionName: 'redeemExpired',
  })

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"removeOption"`
 */
export const useSimulateYieldVaultRemoveOption =
  /*#__PURE__*/ createUseSimulateContract({
    abi: yieldVaultAbi,
    functionName: 'removeOption',
  })

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"renounceOwnership"`
 */
export const useSimulateYieldVaultRenounceOwnership =
  /*#__PURE__*/ createUseSimulateContract({
    abi: yieldVaultAbi,
    functionName: 'renounceOwnership',
  })

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"requestRedeem"`
 */
export const useSimulateYieldVaultRequestRedeem =
  /*#__PURE__*/ createUseSimulateContract({
    abi: yieldVaultAbi,
    functionName: 'requestRedeem',
  })

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"setOperator"`
 */
export const useSimulateYieldVaultSetOperator =
  /*#__PURE__*/ createUseSimulateContract({
    abi: yieldVaultAbi,
    functionName: 'setOperator',
  })

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"setupFactoryApproval"`
 */
export const useSimulateYieldVaultSetupFactoryApproval =
  /*#__PURE__*/ createUseSimulateContract({
    abi: yieldVaultAbi,
    functionName: 'setupFactoryApproval',
  })

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"transfer"`
 */
export const useSimulateYieldVaultTransfer =
  /*#__PURE__*/ createUseSimulateContract({
    abi: yieldVaultAbi,
    functionName: 'transfer',
  })

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"transferFrom"`
 */
export const useSimulateYieldVaultTransferFrom =
  /*#__PURE__*/ createUseSimulateContract({
    abi: yieldVaultAbi,
    functionName: 'transferFrom',
  })

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"transferOwnership"`
 */
export const useSimulateYieldVaultTransferOwnership =
  /*#__PURE__*/ createUseSimulateContract({
    abi: yieldVaultAbi,
    functionName: 'transferOwnership',
  })

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link yieldVaultAbi}__ and `functionName` set to `"unpause"`
 */
export const useSimulateYieldVaultUnpause =
  /*#__PURE__*/ createUseSimulateContract({
    abi: yieldVaultAbi,
    functionName: 'unpause',
  })

/**
 * Wraps __{@link useWatchContractEvent}__ with `abi` set to __{@link yieldVaultAbi}__
 */
export const useWatchYieldVaultEvent =
  /*#__PURE__*/ createUseWatchContractEvent({ abi: yieldVaultAbi })

/**
 * Wraps __{@link useWatchContractEvent}__ with `abi` set to __{@link yieldVaultAbi}__ and `eventName` set to `"Approval"`
 */
export const useWatchYieldVaultApprovalEvent =
  /*#__PURE__*/ createUseWatchContractEvent({
    abi: yieldVaultAbi,
    eventName: 'Approval',
  })

/**
 * Wraps __{@link useWatchContractEvent}__ with `abi` set to __{@link yieldVaultAbi}__ and `eventName` set to `"Deposit"`
 */
export const useWatchYieldVaultDepositEvent =
  /*#__PURE__*/ createUseWatchContractEvent({
    abi: yieldVaultAbi,
    eventName: 'Deposit',
  })

/**
 * Wraps __{@link useWatchContractEvent}__ with `abi` set to __{@link yieldVaultAbi}__ and `eventName` set to `"OperatorSet"`
 */
export const useWatchYieldVaultOperatorSetEvent =
  /*#__PURE__*/ createUseWatchContractEvent({
    abi: yieldVaultAbi,
    eventName: 'OperatorSet',
  })

/**
 * Wraps __{@link useWatchContractEvent}__ with `abi` set to __{@link yieldVaultAbi}__ and `eventName` set to `"OptionAdded"`
 */
export const useWatchYieldVaultOptionAddedEvent =
  /*#__PURE__*/ createUseWatchContractEvent({
    abi: yieldVaultAbi,
    eventName: 'OptionAdded',
  })

/**
 * Wraps __{@link useWatchContractEvent}__ with `abi` set to __{@link yieldVaultAbi}__ and `eventName` set to `"OptionRemoved"`
 */
export const useWatchYieldVaultOptionRemovedEvent =
  /*#__PURE__*/ createUseWatchContractEvent({
    abi: yieldVaultAbi,
    eventName: 'OptionRemoved',
  })

/**
 * Wraps __{@link useWatchContractEvent}__ with `abi` set to __{@link yieldVaultAbi}__ and `eventName` set to `"OptionsBurned"`
 */
export const useWatchYieldVaultOptionsBurnedEvent =
  /*#__PURE__*/ createUseWatchContractEvent({
    abi: yieldVaultAbi,
    eventName: 'OptionsBurned',
  })

/**
 * Wraps __{@link useWatchContractEvent}__ with `abi` set to __{@link yieldVaultAbi}__ and `eventName` set to `"Paused"`
 */
export const useWatchYieldVaultPausedEvent =
  /*#__PURE__*/ createUseWatchContractEvent({
    abi: yieldVaultAbi,
    eventName: 'Paused',
  })

/**
 * Wraps __{@link useWatchContractEvent}__ with `abi` set to __{@link yieldVaultAbi}__ and `eventName` set to `"RedeemRequest"`
 */
export const useWatchYieldVaultRedeemRequestEvent =
  /*#__PURE__*/ createUseWatchContractEvent({
    abi: yieldVaultAbi,
    eventName: 'RedeemRequest',
  })

/**
 * Wraps __{@link useWatchContractEvent}__ with `abi` set to __{@link yieldVaultAbi}__ and `eventName` set to `"Transfer"`
 */
export const useWatchYieldVaultTransferEvent =
  /*#__PURE__*/ createUseWatchContractEvent({
    abi: yieldVaultAbi,
    eventName: 'Transfer',
  })

/**
 * Wraps __{@link useWatchContractEvent}__ with `abi` set to __{@link yieldVaultAbi}__ and `eventName` set to `"Unpaused"`
 */
export const useWatchYieldVaultUnpausedEvent =
  /*#__PURE__*/ createUseWatchContractEvent({
    abi: yieldVaultAbi,
    eventName: 'Unpaused',
  })

/**
 * Wraps __{@link useWatchContractEvent}__ with `abi` set to __{@link yieldVaultAbi}__ and `eventName` set to `"Withdraw"`
 */
export const useWatchYieldVaultWithdrawEvent =
  /*#__PURE__*/ createUseWatchContractEvent({
    abi: yieldVaultAbi,
    eventName: 'Withdraw',
  })
