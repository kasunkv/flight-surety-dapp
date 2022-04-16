import FlightSuretyApp from '../../build/contracts/FlightSuretyApp.json';
import Config from './config.json';
import Web3 from 'web3';

export default class Contract {
	constructor(network, callback) {

			let config = Config[network];
			this.web3 = new Web3(new Web3.providers.HttpProvider(config.url));
			this.flightSuretyApp = new this.web3.eth.Contract(FlightSuretyApp.abi, config.appAddress);
			this.initialize(callback);
			this.owner = null;
			this.airlines = [];
			this.passengers = [];
	}

	initialize(callback) {
			this.web3.eth.getAccounts((error, accts) => {

					this.owner = accts[0];
					console.log(`Owner: ${this.owner}`);

					let counter = 1;

					while (this.airlines.length < 5) {
							this.airlines.push(accts[counter++]);
					}

					while (this.passengers.length < 5) {
							this.passengers.push(accts[counter++]);
					}

					callback();
			});
	}

	isOperational(callback) {
			let self = this;
			self.flightSuretyApp.methods
					.isOperational()
					.call({ from: self.owner }, callback);
	}

	registerAirline(airlineAddress, airlineName, callback) {
			let self = this;
			self.flightSuretyApp.methods
					.registerAirline(airlineAddress, airlineName)
					.send({ from: self.owner, gas: 6721900 }, callback);
	}

	fundAirline(airlineAddress, callback) {
			let self = this;
			const fee = this.web3.utils.toWei('10', 'ether');
			self.flightSuretyApp.methods
					.fundAirline()
					.send({ from: airlineAddress, value: fee }, callback);
	}

	voteForAirline(airlineAddress, callback) {
			let self = this;
			self.flightSuretyApp.methods
					.voteForAirline(airlineAddress)
					.send({ from: self.owner, gas: 6721900 }, callback);
	}

	isAirlineRegistered(airlineAddress, callback) {
			let self = this;
			self.flightSuretyApp.methods
					.isAirlineRegistered(airlineAddress)
					.call({ from: self.owner }, callback);
	}

	isAirlineFunded(airlineAddress, callback) {
			let self = this;
			self.flightSuretyApp.methods
					.isAirlineFunded(airlineAddress)
					.call({ from: self.owner }, callback);
	}

	isAirlineApproved(airlineAddress, callback) {
			let self = this;
			self.flightSuretyApp.methods
					.isAirlineApproved(airlineAddress)
					.call({ from: self.owner }, callback);
	}

	buyInsurancePolicy(airlineAddress, flightName, timestamp, amount, callback) {
			let self = this;
			const insuredAmount = this.web3.utils.toWei(amount, 'ether');
			self.flightSuretyApp.methods
					.buyInsurancePolicy(airlineAddress, flightName, timestamp)
					.send({ from: self.owner, gas: 6721900, value: insuredAmount }, callback);
	}

	fetchFlightStatus(flightName, airlineAddress, timestamp, callback) {
			let self = this;
			let payload = {
					airline: airlineAddress,
					flight: flightName,
					timestamp: timestamp
			}
			self.flightSuretyApp.methods
					.fetchFlightStatus(payload.airline, payload.flight, payload.timestamp)
					.send({ from: self.owner }, (error, result) => {
							callback(error, payload);
					});
	}

	getPassengerEntitlement(passangerAddress, callback) {
			let self = this;
			self.flightSuretyApp.methods
					.getPassengerEntitlement(passangerAddress)
					.call({ from: self.owner }, callback);
	}

	withdrawIsuranceClaim(pessangerAddress, callback) {
			let self = this;
			self.flightSuretyApp.methods
					.withdrawIsuranceClaim(pessangerAddress)
					.send({ from: self.owner }, (error, result) => {
							callback(error, result);
					});
	}
}
