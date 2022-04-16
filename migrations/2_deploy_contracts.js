const FlightSuretyApp = artifacts.require("FlightSuretyApp");
const FlightSuretyData = artifacts.require("FlightSuretyData");
const fs = require('fs');

module.exports = function(deployer) {
		deployer.then(async() => {
			const flightSuretyData = await deployer.deploy(FlightSuretyData);
			await deployer.deploy(FlightSuretyApp, flightSuretyData.address);
		});
}