import FlightSuretyApp from '../../build/contracts/FlightSuretyApp.json';
import Config from './config.json';
import Web3 from 'web3';
import express from 'express';
import 'babel-polyfill';

let config = Config['localhost'];
let web3 = new Web3(new Web3.providers.WebsocketProvider(config.url.replace('http', 'ws')));
web3.eth.defaultAccount = web3.eth.accounts[0];
let flightSuretyApp = new web3.eth.Contract(FlightSuretyApp.abi, config.appAddress);

async function registerOracles() {
  const fee = await flightSuretyApp.methods.oracleRegistrationFee().call();
  const accounts = await web3.eth.getAccounts();
  let oracleCount = 0;
  for (const account of accounts) {
    if (oracleCount > 9) {
      break;
    }

    console.log('account=', account);
    await flightSuretyApp.methods.registerOracle().send({
      from: account,
      value: fee,
      gas: 6721974,
      gasPrice: 0,
    });

    oracleCount++;
  }
  console.log('[', +oracleCount + '] Oracles registered');
}

async function simulateOracleResponse(requestedIndex, airline, flight, timestamp) {
  const accounts = await web3.eth.getAccounts();
  let oracleCount = 0;
  for (const account of accounts) {
    var indexes = await flightSuretyApp.methods.getMyIndexes().call({ from: account });
    console.log('Oracles indexes: ' + indexes + ' for account: ' + account);
    for (const index of indexes) {
      if (oracleCount > 9) {
        break;
      }

      try {
        if (requestedIndex == index) {
          console.log('Submitting Oracle response For Flight: ' + flight + ' at Index: ' + index);
          await flightSuretyApp.methods.submitOracleResponse(index, airline, flight, timestamp, 20).send({ from: account, gas: 6721900 });
        }
      } catch (e) {
        console.log(e);
      }

      oracleCount++;
    }
  }
}

registerOracles();

flightSuretyApp.events.OracleRequest({}, async (error, event) => {
  if (error) {
    console.log(error);
    return;
  }

  await simulateOracleResponse(event.returnValues[0], event.returnValues[1], event.returnValues[2], event.returnValues[3]);

  console.log(event);
});

flightSuretyApp.events.FlightStatusInfo({}).on('data', async (event, error) => {
  console.log('event=', event);
  console.log('error=', error);
});

const app = express();
app.get('/api', (req, res) => {
  res.send({
    message: 'An API for use with your Dapp!',
  });
});

export default app;
