pragma solidity 0.7.0;

import "./IERC20.sol";
import "./IMintableToken.sol";
import "./IDividends.sol";
import "./SafeMath.sol";

contract Token is IERC20, IMintableToken, IDividends {
  // ------------------------------------------ //
  // ----- BEGIN: DO NOT EDIT THIS SECTION ---- //
  // ------------------------------------------ //
  using SafeMath for uint256;
  uint256 public totalSupply;
  uint256 public decimals = 18;
  string public name = "Test token";
  string public symbol = "TEST";
  mapping (address => uint256) public balanceOf;
  // ------------------------------------------ //
  // ----- END: DO NOT EDIT THIS SECTION ------ //  
  // ------------------------------------------ //

  // --- Declaring Events inside the Allowed Section to Fix Compilation Errors ---
  event Transfer(address indexed from, address indexed to, uint256 value);
  event Approval(address indexed owner, address indexed spender, uint256 value);

  
  mapping(address => mapping(address => uint256)) public override allowance;

  uint256 public totalDividendPoints;
  uint256 public constant POINT_MULTIPLIER = 10**18;
  mapping(address => uint256) public lastDividendPoints;
  mapping(address => uint256) public savedDividends;

  address[] private holdersIndex;
  mapping(address => uint256) private holderPositions;

  // --- Holder Management ---
  function _addHolder(address _account) internal {
      if (holderPositions[_account] == 0) {
          holdersIndex.push(_account);
          holderPositions[_account] = holdersIndex.length;
      }
  }

  function _removeHolder(address _account) internal {
      if (balanceOf[_account] == 0 && holderPositions[_account] != 0) {
          uint256 indexToRemove = holderPositions[_account].sub(1);
          uint256 lastIndex = holdersIndex.length.sub(1);

          if (indexToRemove != lastIndex) {
              address lastHolder = holdersIndex[lastIndex];
              holdersIndex[indexToRemove] = lastHolder;
              holderPositions[lastHolder] = indexToRemove.add(1);
          }

          holdersIndex.pop();
          delete holderPositions[_account];
      }
  }

  // --- Dividend Processing using SafeMath ---
  function _updateDividend(address _account) internal {
      uint256 balance = balanceOf[_account];
      if (balance > 0) {
          uint256 owing = totalDividendPoints.sub(lastDividendPoints[_account]);
          if (owing > 0) {
              savedDividends[_account] = savedDividends[_account].add((balance.mul(owing)).div(POINT_MULTIPLIER));
          }
      }
      lastDividendPoints[_account] = totalDividendPoints;
  }

  // --- IMintableToken Logic ---
  function mint() external payable override {
      require(msg.value > 0, "Cannot mint 0 tokens");
      _updateDividend(msg.sender);

      balanceOf[msg.sender] = balanceOf[msg.sender].add(msg.value);
      totalSupply = totalSupply.add(msg.value);
      
      _addHolder(msg.sender);
      emit Transfer(address(0), msg.sender, msg.value);
  }

  function burn(address payable _refundAddress) external override {
      require(balanceOf[msg.sender] > 0, "No tokens to burn");
      _updateDividend(msg.sender);

      uint256 burnAmount = balanceOf[msg.sender];
      balanceOf[msg.sender] = 0;
      totalSupply = totalSupply.sub(burnAmount);

      _removeHolder(msg.sender);
      emit Transfer(msg.sender, address(0), burnAmount);

      (bool success, ) = _refundAddress.call{value: burnAmount}("");
      require(success, "Refund transfer failed");
  }

  // --- IDividends Logic ---
  function recordDividend() external payable override {
      require(msg.value > 0, "Empty dividend disallowed");
      require(totalSupply > 0, "No tokens minted yet");

      totalDividendPoints = totalDividendPoints.add((msg.value.mul(POINT_MULTIPLIER)).div(totalSupply));
  }

  function withdrawDividend(address payable _destination) external override {
      _updateDividend(msg.sender);

      uint256 amount = savedDividends[msg.sender];
      require(amount > 0, "No dividends to withdraw");
      
      savedDividends[msg.sender] = 0;

      (bool success, ) = _destination.call{value: amount}("");
      require(success, "Dividend withdrawal failed");
  }

  function getWithdrawableDividend(address _account) external view override returns (uint256) {
      uint256 owing = totalDividendPoints.sub(lastDividendPoints[_account]);
      return savedDividends[_account].add((balanceOf[_account].mul(owing)).div(POINT_MULTIPLIER));
  }

  function getNumTokenHolders() external view override returns (uint256) {
      return holdersIndex.length;
  }

  function getTokenHolder(uint256 _index) external view override returns (address) {
      if (_index < 1 || _index > holdersIndex.length) {
          return address(0);
      }
      return holdersIndex[_index - 1];
  }

  // --- IERC20 Core Logic ---
  function transfer(address _to, uint256 _value) external override returns (bool) {
      require(balanceOf[msg.sender] >= _value, "Insufficient balance");
      
      _updateDividend(msg.sender);
      _updateDividend(_to);

      balanceOf[msg.sender] = balanceOf[msg.sender].sub(_value);
      balanceOf[_to] = balanceOf[_to].add(_value);

      if (_value > 0) {
          _addHolder(_to);
          _removeHolder(msg.sender);
      }

      emit Transfer(msg.sender, _to, _value);
      return true;
  }

  function approve(address _spender, uint256 _value) external override returns (bool) {
      allowance[msg.sender][_spender] = _value;
      emit Approval(msg.sender, _spender, _value);
      return true;
  }

  function transferFrom(address _from, address _to, uint256 _value) external override returns (bool) {
      require(balanceOf[_from] >= _value, "Insufficient balance");
      require(allowance[_from][msg.sender] >= _value, "Allowance exceeded");

      _updateDividend(_from);
      _updateDividend(_to);

      allowance[_from][msg.sender] = allowance[_from][msg.sender].sub(_value);
      balanceOf[_from] = balanceOf[_from].sub(_value);
      balanceOf[_to] = balanceOf[_to].add(_value);

      if (_value > 0) {
          _addHolder(_to);
          _removeHolder(_from);
      }

      emit Transfer(_from, _to, _value);
      return true;
  }
}