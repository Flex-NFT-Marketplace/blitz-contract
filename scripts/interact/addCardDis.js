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
const factoryABI = require("../abis/CardFactory.json");

const PRIVATE_KEY = "";
const ACCOUNT_ADDRESS =
  "0x05dcb49a8217eab5ed23e4a26df044edaf1428a5c7b30fa2324fa39a28288f6b";
const CONTRACT_ADDRESS = addresses.FACTORY;

const account = new Account(provider, ACCOUNT_ADDRESS, PRIVATE_KEY);

// Helper to convert string to ASCII felt representation
const stringToFelt = (str) => {
  let felt = 0n;
  for (let i = 0; i < str.length; i++) {
    felt = (felt << 8n) + BigInt(str.charCodeAt(i));
  }
  return felt.toString();
};

// Helper to flatten a CardDistribution struct
const flattenCardDistribution = (card) => {
  const { token_id, name, class: cardClass, rarity, rate } = card;

  // token_id and rate are u256, so we split them into two 128-bit numbers
  const tokenIdLow = token_id.low.toString();
  const tokenIdHigh = token_id.high.toString();
  const rateLow = rate.low.toString();
  const rateHigh = rate.high.toString();

  return [
    tokenIdLow,
    tokenIdHigh, // u256 (token_id)
    stringToFelt(name), // felt (name as ASCII/UTF-8)
    cardClass.toString(), // felt (class)
    rarity.toString(), // felt (rarity)
    rateLow,
    rateHigh, // u256 (rate)
  ];
};

async function addCardDistributions() {
  try {
    console.log("🚀 Interacting with CardFactory at: " + CONTRACT_ADDRESS);
    console.log("🧑‍💼 Using Account: " + account.address);

    const cardFactory = new Contract(factoryABI, CONTRACT_ADDRESS, provider);
    cardFactory.connect(account);

    const collectibleAddress = addresses.COLLECTIBLE;
    const phaseId = uint256.bnToUint256(2); // Phase ID (u256)

    const cardDistributions = [
      {
        token_id: uint256.bnToUint256(1),
        name: "Imhotep",
        class: 1,
        rarity: 124,
        rate: uint256.bnToUint256(12400),
      },
      {
        token_id: uint256.bnToUint256(2),
        name: "Akhir",
        class: 1,
        rarity: 113,
        rate: uint256.bnToUint256(11399),
      },
      {
        token_id: uint256.bnToUint256(3),
        name: "Nefru",
        class: 1,
        rarity: 113,
        rate: uint256.bnToUint256(11399),
      },
      {
        token_id: uint256.bnToUint256(4),
        name: "Nephthys",
        class: 2,
        rarity: 113,
        rate: uint256.bnToUint256(11399),
      },
      {
        token_id: uint256.bnToUint256(5),
        name: "Bastet",
        class: 2,
        rarity: 113,
        rate: uint256.bnToUint256(11399),
      },
      {
        token_id: uint256.bnToUint256(6),
        name: "Anmit",
        class: 2,
        rarity: 113,
        rate: uint256.bnToUint256(11399),
      },
      {
        token_id: uint256.bnToUint256(7),
        name: "Sebek",
        class: 2,
        rarity: 113,
        rate: uint256.bnToUint256(11399),
      },
      {
        token_id: uint256.bnToUint256(8),
        name: "Horus",
        class: 3,
        rarity: 600,
        rate: uint256.bnToUint256(60000),
      },
      {
        token_id: uint256.bnToUint256(9),
        name: "Horus",
        class: 4,
        rarity: 400,
        rate: uint256.bnToUint256(40000),
      },
      {
        token_id: uint256.bnToUint256(10),
        name: "Horus",
        class: 5,
        rarity: 200,
        rate: uint256.bnToUint256(20000),
      },
      {
        token_id: uint256.bnToUint256(11),
        name: "Achilles",
        class: 1,
        rarity: 113,
        rate: uint256.bnToUint256(11399),
      },
      {
        token_id: uint256.bnToUint256(12),
        name: "Minotaur",
        class: 1,
        rarity: 113,
        rate: uint256.bnToUint256(11399),
      },
      {
        token_id: uint256.bnToUint256(13),
        name: "Penthesilea",
        class: 1,
        rarity: 113,
        rate: uint256.bnToUint256(11399),
      },
      {
        token_id: uint256.bnToUint256(14),
        name: "Medusa",
        class: 2,
        rarity: 113,
        rate: uint256.bnToUint256(11399),
      },
      {
        token_id: uint256.bnToUint256(15),
        name: "Zeus",
        class: 2,
        rarity: 113,
        rate: uint256.bnToUint256(11399),
      },
      {
        token_id: uint256.bnToUint256(16),
        name: "Athena",
        class: 2,
        rarity: 113,
        rate: uint256.bnToUint256(11399),
      },
      {
        token_id: uint256.bnToUint256(17),
        name: "Apolo",
        class: 2,
        rarity: 113,
        rate: uint256.bnToUint256(11399),
      },
      {
        token_id: uint256.bnToUint256(18),
        name: "Phobosyn",
        class: 3,
        rarity: 600,
        rate: uint256.bnToUint256(60000),
      },
      {
        token_id: uint256.bnToUint256(19),
        name: "Phobosyn",
        class: 4,
        rarity: 400,
        rate: uint256.bnToUint256(40000),
      },
      {
        token_id: uint256.bnToUint256(20),
        name: "Phobosyn",
        class: 5,
        rarity: 200,
        rate: uint256.bnToUint256(20000),
      },
      {
        token_id: uint256.bnToUint256(21),
        name: "Mokumokuren",
        class: 1,
        rarity: 113,
        rate: uint256.bnToUint256(11399),
      },
      {
        token_id: uint256.bnToUint256(22),
        name: "Tengu",
        class: 1,
        rarity: 113,
        rate: uint256.bnToUint256(11399),
      },
      {
        token_id: uint256.bnToUint256(23),
        name: "Kasa Obake",
        class: 1,
        rarity: 113,
        rate: uint256.bnToUint256(11399),
      },
      {
        token_id: uint256.bnToUint256(24),
        name: "Izanami",
        class: 2,
        rarity: 113,
        rate: uint256.bnToUint256(11399),
      },
      {
        token_id: uint256.bnToUint256(25),
        name: "Amaterasu",
        class: 2,
        rarity: 113,
        rate: uint256.bnToUint256(11399),
      },
      {
        token_id: uint256.bnToUint256(26),
        name: "Raijin",
        class: 2,
        rarity: 113,
        rate: uint256.bnToUint256(11399),
      },
      {
        token_id: uint256.bnToUint256(27),
        name: "Susanoo",
        class: 2,
        rarity: 113,
        rate: uint256.bnToUint256(11399),
      },
      {
        token_id: uint256.bnToUint256(28),
        name: "Tsukoyomi",
        class: 3,
        rarity: 600,
        rate: uint256.bnToUint256(60000),
      },
      {
        token_id: uint256.bnToUint256(29),
        name: "Tsukoyomi",
        class: 4,
        rarity: 400,
        rate: uint256.bnToUint256(40000),
      },
      {
        token_id: uint256.bnToUint256(30),
        name: "Tsukoyomi",
        class: 5,
        rarity: 200,
        rate: uint256.bnToUint256(20000),
      },
      {
        token_id: uint256.bnToUint256(31),
        name: "Blódulf",
        class: 1,
        rarity: 113,
        rate: uint256.bnToUint256(11399),
      },
      {
        token_id: uint256.bnToUint256(32),
        name: "Nidrmál",
        class: 1,
        rarity: 113,
        rate: uint256.bnToUint256(11399),
      },
      {
        token_id: uint256.bnToUint256(33),
        name: "Skog",
        class: 1,
        rarity: 113,
        rate: uint256.bnToUint256(11399),
      },
      {
        token_id: uint256.bnToUint256(34),
        name: "Nidhogg",
        class: 2,
        rarity: 113,
        rate: uint256.bnToUint256(11399),
      },
      {
        token_id: uint256.bnToUint256(35),
        name: "Hercules",
        class: 2,
        rarity: 113,
        rate: uint256.bnToUint256(11399),
      },
      {
        token_id: uint256.bnToUint256(36),
        name: "Magni",
        class: 2,
        rarity: 113,
        rate: uint256.bnToUint256(11399),
      },
      {
        token_id: uint256.bnToUint256(37),
        name: "Odin",
        class: 2,
        rarity: 113,
        rate: uint256.bnToUint256(11399),
      },
      {
        token_id: uint256.bnToUint256(38),
        name: "Tyr",
        class: 3,
        rarity: 600,
        rate: uint256.bnToUint256(60000),
      },
      {
        token_id: uint256.bnToUint256(39),
        name: "Tyr",
        class: 4,
        rarity: 400,
        rate: uint256.bnToUint256(40000),
      },
      {
        token_id: uint256.bnToUint256(40),
        name: "Tyr",
        class: 5,
        rarity: 200,
        rate: uint256.bnToUint256(20000),
      },
      {
        token_id: uint256.bnToUint256(41),
        name: "Abaddon",
        class: 1,
        rarity: 113,
        rate: uint256.bnToUint256(11399),
      },
      {
        token_id: uint256.bnToUint256(42),
        name: "Belial",
        class: 1,
        rarity: 113,
        rate: uint256.bnToUint256(11399),
      },
      {
        token_id: uint256.bnToUint256(43),
        name: "Dantalion",
        class: 1,
        rarity: 113,
        rate: uint256.bnToUint256(11399),
      },
      {
        token_id: uint256.bnToUint256(44),
        name: "Gremory",
        class: 2,
        rarity: 113,
        rate: uint256.bnToUint256(11399),
      },
      {
        token_id: uint256.bnToUint256(45),
        name: "Asmodeus",
        class: 2,
        rarity: 113,
        rate: uint256.bnToUint256(11399),
      },
      {
        token_id: uint256.bnToUint256(46),
        name: "Jinn",
        class: 2,
        rarity: 113,
        rate: uint256.bnToUint256(11399),
      },
      {
        token_id: uint256.bnToUint256(47),
        name: "Lilith",
        class: 2,
        rarity: 113,
        rate: uint256.bnToUint256(11399),
      },
      {
        token_id: uint256.bnToUint256(48),
        name: "Barbatos",
        class: 3, // Legendary
        rarity: 600,
        rate: uint256.bnToUint256(60000),
      },
      {
        token_id: uint256.bnToUint256(49),
        name: "Barbatos",
        class: 4, // Mythical
        rarity: 400,
        rate: uint256.bnToUint256(40000),
      },
      {
        token_id: uint256.bnToUint256(50),
        name: "Barbatos",
        class: 5,
        rarity: 200,
        rate: uint256.bnToUint256(20000),
      },
    ];

    // Flatten the CardDistribution objects
    const flattenedCards = cardDistributions.flatMap(flattenCardDistribution);
    // Add the length of the array at the start
    const calldata = [
      collectibleAddress, // Contract address
      phaseId, // u256 Phase ID
      cardDistributions.length.toString(), // Length of the cards array
      ...flattenedCards, // Flattened array of cards
    ];

    console.log("📦 Calldata for add_card_distributions:", calldata);

    const result = await account.execute({
      contractAddress: CONTRACT_ADDRESS,
      entrypoint: "add_card_distributions",
      calldata: calldata,
    });

    const txReceipt = await provider.waitForTransaction(
      result.transaction_hash
    );
    console.log("🎉 Transaction Confirmed on StarkNet!", txReceipt);
  } catch (error) {
    console.error("❌ Error while interacting with the contract:", error);
  }
}

addCardDistributions();
