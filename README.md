# Flight Surety dApp - Udacity Blockchain Developer Nano-Degree Program
Flight Surety dApp is a flight insurance application  project given as part of the Udacity Blockchain Developer Nano-Degree Program


## Environment
- Node v16.13.1
- Yarn v1.22.17


## Libraries Used
- Truffle v5.5.6
- Ganache v7.0.3
- Solidity v0.8.10
- Web3.js v1.5.3
- Webpack v5.72.0
- Truffle Assertions v0.9.2


## Run Locally

1. On the project root run `yarn`
2. To compile the smart contracts run `yarn compile`
3. To run the migrations run `yarn migrate`
4. To execute the unit tests, run `yarn test`
5. Update the `config.json` files found under `src/dapp` and `src/server` and modify the `url` property to point to the local ganache instance and `appAddress` property to point to the deployed `FlightSuretyApp` smart contract.
6. To run the server, run `yarn server`
7. To run the dApp in the development mode, run `yarn dapp`