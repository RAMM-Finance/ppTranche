pragma solidity ^0.8.9;
import {ERC4626} from "./vaults/mixins/ERC4626.sol";

import {SafeCastLib} from "./vaults/utils/SafeCastLib.sol";
import {SafeTransferLib} from "./vaults/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "./vaults/utils/FixedPointMathLib.sol";

import {IERC3156FlashBorrower} from "./vaults/tokens/ERC1155.sol"; 
import {ERC20} from "./vaults/tokens/ERC20.sol";
import {tVault} from "./tVault.sol"; 
import {TrancheMaster} from "./tranchemaster.sol"; 
import "forge-std/console.sol";
import "./vaults/utils/oz.sol"; 

/// @notice tokens for junior/senior tranches 
contract tToken is ERC20{

  modifier onlySplitter() {
    require(msg.sender == splitter, "!Splitter");
    _;
    }

    address splitter; 
    ERC20 asset; 

  /// @notice asset is the tVault  
    constructor(
        ERC20 _asset, 
        string memory _name,
        string memory _symbol, 
        address _splitter
        ) ERC20(_name, _symbol, _asset.decimals()) {
        asset = _asset;
        splitter = _splitter; 
    }

    function mint(address to, uint256 amount) external onlySplitter{
        _mint(to, amount); 
    }

    function burn(address from, uint256 amount) external onlySplitter{
        _burn(from, amount);
    }

    function flashMint(
        IERC3156FlashBorrower receiver,
        address token, 
        uint256 amount, 
        bytes calldata data
        ) external returns(bool){
        //require(amount <= max);
        _mint(address(receiver), amount); 
        require(
            receiver.onFlashLoan(msg.sender, address(this), amount, 0, data) 
            == keccak256("ERC3156FlashBorrower.onFlashLoan"), "callback failed"
            ); 
        _burn(address(receiver), amount); 
    }




    using Arrays for uint256[];
    using Counters for Counters.Counter;

    // Snapshotted values have arrays of ids and the value corresponding to that id. These could be an array of a
    // Snapshot struct, but that would impede usage of functions that work on an array.
    struct Snapshots {
        uint256[] ids;
        uint256[] values;
    }

    mapping(address => Snapshots) private _accountBalanceSnapshots;
    Snapshots private _totalSupplySnapshots;

    // Snapshot ids increase monotonically, with the first value being 1. An id of 0 is invalid.
    Counters.Counter private _currentSnapshotId;

 
    event Snapshot(uint256 id);

    function _snapshot() public virtual onlySplitter returns (uint256) {
        _currentSnapshotId.increment();

        uint256 currentId = _getCurrentSnapshotId();
        emit Snapshot(currentId);
        return currentId;
    }

    function _getCurrentSnapshotId() internal view virtual returns (uint256) {
        return _currentSnapshotId.current();
    }

    function balanceOfAt(address account, uint256 snapshotId) public view virtual returns (uint256) {
        (bool snapshotted, uint256 value) = _valueAt(snapshotId, _accountBalanceSnapshots[account]);

        return snapshotted ? value : balanceOf[account];
    }

    function totalSupplyAt(uint256 snapshotId) public view virtual returns (uint256) {
        (bool snapshotted, uint256 value) = _valueAt(snapshotId, _totalSupplySnapshots);

        return snapshotted ? value : totalSupply;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual  {
       // super._beforeTokenTransfer(from, to, amount);

        if (from == address(0)) {
            // mint
            _updateAccountSnapshot(to);
            _updateTotalSupplySnapshot();
        } else if (to == address(0)) {
            // burn
            _updateAccountSnapshot(from);
            _updateTotalSupplySnapshot();
        } else {
            // transfer
            _updateAccountSnapshot(from);
            _updateAccountSnapshot(to);
        }
    }

    function _valueAt(uint256 snapshotId, Snapshots storage snapshots) private view returns (bool, uint256) {
        require(snapshotId > 0, "ERC20Snapshot: id is 0");
        require(snapshotId <= _getCurrentSnapshotId(), "ERC20Snapshot: nonexistent id");

        // When a valid snapshot is queried, there are three possibilities:
        //  a) The queried value was not modified after the snapshot was taken. Therefore, a snapshot entry was never
        //  created for this id, and all stored snapshot ids are smaller than the requested one. The value that corresponds
        //  to this id is the current one.
        //  b) The queried value was modified after the snapshot was taken. Therefore, there will be an entry with the
        //  requested id, and its value is the one to return.
        //  c) More snapshots were created after the requested one, and the queried value was later modified. There will be
        //  no entry for the requested id: the value that corresponds to it is that of the smallest snapshot id that is
        //  larger than the requested one.
        //
        // In summary, we need to find an element in an array, returning the index of the smallest value that is larger if
        // it is not found, unless said value doesn't exist (e.g. when all values are smaller). Arrays.findUpperBound does
        // exactly this.

        uint256 index = snapshots.ids.findUpperBound(snapshotId);

        if (index == snapshots.ids.length) {
            return (false, 0);
        } else {
            return (true, snapshots.values[index]);
        }
    }

    function _updateAccountSnapshot(address account) private {
        _updateSnapshot(_accountBalanceSnapshots[account], balanceOf[account]);
    }

    function _updateTotalSupplySnapshot() private {
        _updateSnapshot(_totalSupplySnapshots, totalSupply);
    }

    function _updateSnapshot(Snapshots storage snapshots, uint256 currentValue) private {
        uint256 currentId = _getCurrentSnapshotId();
        if (_lastSnapshotId(snapshots.ids) < currentId) {
            snapshots.ids.push(currentId);
            snapshots.values.push(currentValue);
        }
    }

    function _lastSnapshotId(uint256[] storage ids) private view returns (uint256) {
        if (ids.length == 0) {
            return 0;
        } else {
            return ids[ids.length - 1];
        }
    }



}





