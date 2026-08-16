module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.8.24",
        settings: { optimizer: { enabled: true, runs: 200 } }
      }
    ]
  },
  networks: {
    localhost: { url: "http://127.0.0.1:8545" }
  }
};
