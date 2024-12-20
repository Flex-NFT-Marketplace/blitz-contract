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

    // 1️⃣ Convert base_uri to ByteArray
    const baseUri = "https://api.example.com/v1/";
    //const totalSupply = 10n * 10n ** 18n; // 10 * 1e18

    // 1️⃣ Convert baseUri to ByteArray
    const baseUriBytes = Array.from(baseUri).map((char) => char.charCodeAt(0));
    const baseUriLength = baseUriBytes.length;
    console.log("📝 Base URI (as byte array):", baseUriBytes);

    // 2️⃣ Convert total supply to u256 (low, high)
    const totalSupplyU256 = uint256.bnToUint256(totalSupply);
    console.log("📈 Total Supply (u256):", totalSupplyU256);

    // 4️⃣ Execute the transaction
    const result = await account.execute({
      contractAddress: CONTRACT_ADDRESS,
      entrypoint: "create_card_collectible",
      calldata: CallData.compile({
        base_uri: byteArray.byteArrayFromString(baseUri),
        pack_address: packAddress,
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
