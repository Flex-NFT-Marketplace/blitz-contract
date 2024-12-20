const {
  Account,
  Contract,
  RpcProvider,
  json,
  uint256,
  CallData,
  cairo,
  byteArray,
  constants,
} = require("starknet");
const fs = require("fs");
const factoryABI = require("../abis/CardFactory.json");
const { addresses } = require("../utils/constants");

async function createCardCollectible() {
  const baseUri = "https://api.example.com/v1/";
  const totalSupply = 1000n; // Total supply as BigInt
  const packAddress = addresses.PACK;

  try {
    const RPC = "https://starknet-sepolia.public.blastapi.io/rpc/v0_7";
    const provider = new RpcProvider({ nodeUrl: RPC });

    const PRIVATE_KEY = "";
    const ACCOUNT_ADDRESS =
      "0x05dcb49a8217eab5ed23e4a26df044edaf1428a5c7b30fa2324fa39a28288f6b";
    const CONTRACT_ADDRESS = addresses.FACTORY;

    const account = new Account(provider, ACCOUNT_ADDRESS, PRIVATE_KEY);

    // Load the contract ABI
    // const contractAbi = json.parse(
    //   fs
    //     .readFileSync(
    //       "/home/hayden/workplace/atemu/atemu-contract/scripts/abis/CardFactory.json"
    //     )
    //     .toString("ascii")
    // );

    const cardFactory = new Contract(factoryABI, CONTRACT_ADDRESS, provider);
    cardFactory.connect(account);

    // 4️⃣ Execute the transaction
    const result = await account.execute({
      contractAddress: CONTRACT_ADDRESS,
      entrypoint: "unpack_card_collectible",
      calldata: CallData.compile({
        collectible: addresses.COLLECTIBLE,
        phase_id: uint256.bnToUint256(2),
        token_id: uint256.bnToUint256(4),
      }), // Pass flat calldata
    });

    const txReceipt = await provider.waitForTransaction(
      result.transaction_hash
    );
    console.log("🎉 Transaction Confirmed on StarkNet!", txReceipt);
  } catch (error) {
    console.error("❌ Error while interacting with the contract:", error);
  }
}

createCardCollectible();
