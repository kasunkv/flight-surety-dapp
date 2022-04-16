// SPDX-License-Identifier: MIT

pragma solidity >=0.8.10;

interface IFlightSuretyData {
  function isOperational() external view returns (bool);

  function isRegisteredAirline(address _airlineAddr) external view returns (bool);

  function isApprovedAirline(address _airlineAddr) external view returns (bool);

  function isFundedAirline(address _airlineAddr) external view returns (bool);

  function registerAirline(address _origin, address _airlineAddr, string memory _name) external returns (bool);

	function getPassengerEntitlement(address _passengerAddr) external returns (uint);

  function creditInsurees(
    address _airline,
    string memory _flight,
    uint256 _timestamp
  ) external;

  function buy(
    address _airline,
    string memory _flight,
    uint256 _timestamp
  ) external payable;

  function pay(address _passenger) external;

  function fund(address _airlineAddr) external payable;

  function getAirline(address _airline)
    external
    returns (
      string memory name,
      address wallet,
      bool isRegistered,
      bool isApproved,
      uint256 funds,
      uint256 votes
    );
}
