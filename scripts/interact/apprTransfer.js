const {
  Account,
  Contract,
  RpcProvider,
  json,
  uint256,
  CallData,
} = require("starknet");
const fs = require("fs");
const { addresses } = require("../utils/constants");
// StarkNet RPC provider
const RPC = "https://starknet-sepolia.public.blastapi.io/rpc/v0_7";
const provider = new RpcProvider({ nodeUrl: RPC });
const PRIVATE_KEY = "";
const ACCOUNT_ADDRESS = "";
const CONTRACT_ADDRESS = addresses.FACTORY;
const ETH_ADDRESS =
  "0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7";
const account = new Account(provider, ACCOUNT_ADDRESS, PRIVATE_KEY);

async function transfer(toAddress, amount) {
  // Convert the amount to Uint256 format
  const uintAmount = uint256.bnToUint256("10000000000000000");

  // Create the ETH contract instance
  const ethContract = new Contract(
    [
      {
        name: "transfer",
        type: "function",
        inputs: [
          { name: "recipient", type: "felt" },
          { name: "amount", type: "Uint256" },
        ],
        outputs: [{ name: "success", type: "felt" }],
      },
    ],
    ETH_ADDRESS,
    provider
  );

  // Connect the account to the contract
  ethContract.connect(account);

  // Call the transfer function
  const result = await account.execute({
    contractAddress: ETH_ADDRESS,
    entrypoint: "transfer",
    calldata: CallData.compile({
      recipient: CONTRACT_ADDRESS,
      amount: uintAmount,
    }),
  });

  // Wait for the transaction to be confirmed
  await provider.waitForTransaction(result.transaction_hash);
  console.log(`Transfer successful with tx hash: ${result.transaction_hash}`);
}
transfer();
