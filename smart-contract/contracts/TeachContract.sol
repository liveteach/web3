pragma solidity ^0.8.12;

interface ILANDRegistry {
    function encodeTokenId(int x, int y) external pure returns (uint256);

    function decodeTokenId(uint value) external pure returns (int, int);

    function isApprovedForAll(
        address assetHolder,
        address operator
    ) external view returns (bool);

    function isAuthorized(
        address operator,
        uint256 assetId
    ) external view returns (bool);
}

contract TeachContract {
    uint256 private latestClassroomId;

    address private owner;

    constructor() {
        owner = msg.sender;
        latestClassroomId = 1;
    }

    // id generators, start at one so we can determine unassigned.
    function getNewClassroomId() private returns (uint256) {
        return latestClassroomId++;
    }

    // structs
    struct Land {
        uint256 id;
        address classroomAdminId;
        uint256 classroomId;
    }

    struct ClassroomAdmin {
        address walletAddress;
        uint256[] landIds;
        int[][] landCoordinates; // not persisted
        uint256[] classroomIds;
        address[] teacherIds;
    }

    struct Classroom {
        uint256 id;
        string name;
        uint256[] landIds;
        int[][] landCoordinates; // not persisted
        address classroomAdminId;
        address[] teacherIds;
        string guid;
    }

    struct Teacher {
        address walletAddress;
        uint256[] classroomIds;
        address[] classroomAdminIds;
    }

    struct RoleDetail {
        address[] addressArray;
        mapping(address => bool) boolMapping;
    }

    struct RoleMap {
        RoleDetail classroomAdmin;
        RoleDetail teacher;
    }

    struct RegisteredIds {
        uint256[] landsRegisteredToClassroomAdmin;
        mapping(uint256 => bool) landsRegisteredToClassroomAdminBool;
        uint256[] classroom;
        mapping(uint256 => bool) classroomBool;
        uint256[] landsRegisteredToClassroom;
        mapping(uint256 => bool) landsRegisteredToClassroomBool;
    }

    // id to object mappings
    struct IdsToObjects {
        mapping(uint256 => Land) land;
        mapping(address => ClassroomAdmin) classroomAdmin;
        mapping(uint256 => Classroom) classroom;
        mapping(address => Teacher) teacher;
    }

    struct RoleResult {
        // bool student;
        bool teacher;
        bool classroomAdmin;
        // bool landOperator;
    }

    // Error messages
    string public constant ERR_OBJECT_ACCESS =
        "Object doesn't exist or you don't have access to it.";
    string public constant ERR_ROLE_ASSIGNED =
        "Provided wallet already has role.";
    string public constant ERR_OBJECT_EXISTS = "Provided id invalid.";
    string public constant ERR_ACCESS_DENIED =
        "Provided wallet lacks appropriate role.";

    RegisteredIds private registeredIds;
    RoleMap private roleMap;
    IdsToObjects private idsToObjects;

    ILANDRegistry public landRegistry;

    function setLANDRegistry(address _registry) public onlyOwner {
        require(_isContract(_registry), "LAND registry not a contract");
        landRegistry = ILANDRegistry(_registry);
    }

    // PUBLIC UTILITY
    function getRoles() public view returns (RoleResult memory) {
        return
            RoleResult({
                // student: hasRole(STUDENT, msg.sender),
                teacher: hasRole(roleMap.teacher, msg.sender),
                classroomAdmin: hasRole(roleMap.classroomAdmin, msg.sender)
                // landOperator: hasRole(LAND_OPERATOR, msg.sender)
            });
    }

    // OWNER ONLY METHODS

    function allLands() public view onlyOwner returns (uint256[] memory) {
        return registeredIds.landsRegisteredToClassroomAdmin;
    }

    function allClassrooms() public view onlyOwner returns (uint256[] memory) {
        return registeredIds.classroom;
    }

    function allTeachers() public view onlyOwner returns (address[] memory) {
        return roleMap.teacher.addressArray;
    }

    // CLASSROOM ADMIN
    // create

    function isCallerLandOperator(
        uint256[] memory assetIds
    ) private view returns (bool) {
        for (uint256 i = 0; i < assetIds.length; i++) {
            if (!landRegistry.isAuthorized(msg.sender, assetIds[i])) {
                return false;
            }
        }
        return true;
    }

    function createClassroomAdmin(
        address _walletAddress,
        uint256[] memory _landIds
    ) public {
        require(
            isCallerLandOperator(_landIds),
            "You don't have access to this land"
        );
        // check caller is entitled to land TODO
        require(
            !hasRole(roleMap.classroomAdmin, _walletAddress),
            ERR_ROLE_ASSIGNED
        );
        require(
            !areAnyLandIdsAssignedToClassroomAdmin(_landIds, _walletAddress),
            ERR_OBJECT_EXISTS
        );
        registerClassroomAdmin(_walletAddress, _landIds);
    }

    // read
    function isClassroomAdmin(
        address _walletAddress
    ) public view returns (bool) {
        return hasRole(roleMap.classroomAdmin, _walletAddress);
    }

    function getClassroomAdmins()
        public
        view
        returns (ClassroomAdmin[] memory)
    {
        address[] memory registeredClassroomAdminIds = roleMap
            .classroomAdmin
            .addressArray;
        ClassroomAdmin[] memory rtn = new ClassroomAdmin[](
            registeredClassroomAdminIds.length
        );
        for (uint256 i = 0; i < registeredClassroomAdminIds.length; i++) {
            rtn[i] = idsToObjects.classroomAdmin[
                registeredClassroomAdminIds[i]
            ];
            rtn[i].landCoordinates = getCoordinatesFromLandIds(rtn[i].landIds);
        }
        return rtn;
    }

    function getClassroomAdmin(
        address _walletAddress
    ) public view returns (ClassroomAdmin memory) {
        require(isClassroomAdmin(_walletAddress), "Classroom admin not found.");
        ClassroomAdmin memory rtn = idsToObjects.classroomAdmin[_walletAddress];
        rtn.landCoordinates = getCoordinatesFromLandIds(rtn.landIds);
        return rtn;
    }

    // delete

    function deleteClassroomAdmin(address _walletAddress) public {
        // check caller is entitled to land TODO
        require(
            hasRole(roleMap.classroomAdmin, _walletAddress),
            ERR_ACCESS_DENIED
        );
        // remove existing mappings
        unregisterClassroomAdmin(_walletAddress);
    }

    // CLASSROOM
    // create

    function createClassroomLandIds(
        string memory _name,
        uint256[] memory _landIds,
        string memory guid
    ) public onlyRole(roleMap.classroomAdmin) {
        require(
            checkLandIdsSuitableToBeAssignedToClassroom(msg.sender, _landIds),
            ERR_OBJECT_EXISTS
        );
        registerClassroom(
            getNewClassroomId(),
            _name,
            _landIds,
            msg.sender,
            guid
        );
    }

    function createClassroomCoordinates(
        string memory _name,
        int[][] memory coordinatePairs,
        string memory guid
    ) public onlyRole(roleMap.classroomAdmin) {
        uint256[] memory landIds = new uint256[](coordinatePairs.length);
        for (uint256 i = 0; i < coordinatePairs.length; i++) {
            landIds[i] = landRegistry.encodeTokenId(
                coordinatePairs[i][0],
                coordinatePairs[i][1]
            );
        }
        createClassroomLandIds(_name, landIds, guid);
    }

    // read
    function getClassrooms()
        public
        view
        onlyRole(roleMap.classroomAdmin)
        returns (Classroom[] memory)
    {
        uint256[] memory classroomIds = idsToObjects
            .classroomAdmin[msg.sender]
            .classroomIds;
        Classroom[] memory rtn = new Classroom[](classroomIds.length);
        for (uint256 i = 0; i < classroomIds.length; i++) {
            rtn[i] = idsToObjects.classroom[classroomIds[i]];
            rtn[i].landCoordinates = getCoordinatesFromLandIds(rtn[i].landIds);
        }
        return rtn;
    }

    function getClassroom(uint256 id) public view returns (Classroom memory) {
        // check you're entitled to view this classroom
        // either the owning classroom admin
        // or a teacher assigned to this classroom

        require(registeredIds.classroomBool[id], ERR_OBJECT_ACCESS);
        Classroom memory rtn = idsToObjects.classroom[id];
        bool entitledToViewClassroom = false;

        if (hasRole(roleMap.teacher, msg.sender)) {
            for (uint256 i = 0; i < rtn.teacherIds.length; i++) {
                if (msg.sender == rtn.teacherIds[i]) {
                    entitledToViewClassroom = true;
                    break;
                }
            }
        } else if (hasRole(roleMap.classroomAdmin, msg.sender)) {
            entitledToViewClassroom = walletOwnsClassroom(msg.sender, id);
        }
        require(entitledToViewClassroom, ERR_OBJECT_ACCESS);
        rtn.landCoordinates = getCoordinatesFromLandIds(rtn.landIds);
        return rtn;
    }

    // delete
    function deleteClassroom(
        uint256 id
    ) public onlyRole(roleMap.classroomAdmin) {
        // check you're entitled to this classroom
        require(walletOwnsClassroom(msg.sender, id), ERR_OBJECT_ACCESS);
        unregisterClassroom(id);
    }

    // TEACHER

    function createTeacher(
        address walletAddress,
        uint256[] memory classroomIds
    ) public onlyRole(roleMap.classroomAdmin) {
        // check classroom ids belong to this
        // classroom admin
        require(
            checkClassroomIdsSuitableToBeAssignedToTeacher(
                msg.sender,
                classroomIds
            ),
            ERR_OBJECT_EXISTS
        );
        registerTeacher(walletAddress, classroomIds);
    }

    // read
    function getTeachers()
        public
        view
        onlyRole(roleMap.classroomAdmin)
        returns (Teacher[] memory)
    {
        address[] memory teacherIds = idsToObjects
            .classroomAdmin[msg.sender]
            .teacherIds;
        Teacher[] memory rtn = new Teacher[](teacherIds.length);
        for (uint256 i = 0; i < teacherIds.length; i++) {
            rtn[i] = idsToObjects.teacher[teacherIds[i]];
        }
        return rtn;
    }

    function getTeacher(address id) public view returns (Teacher memory) {
        require(hasRole(roleMap.teacher, id), ERR_OBJECT_ACCESS);
        Teacher memory rtn = idsToObjects.teacher[id];
        bool entitledToViewTeacher = false;

        if (hasRole(roleMap.teacher, msg.sender)) {
            if (msg.sender == id) {
                entitledToViewTeacher = true;
            }
        } else if (hasRole(roleMap.classroomAdmin, msg.sender)) {
            entitledToViewTeacher = walletOwnsTeacher(msg.sender, id);
        }
        require(entitledToViewTeacher, ERR_OBJECT_ACCESS);
        return rtn;
    }

    // delete
    function deleteTeacher(address id) public onlyRole(roleMap.classroomAdmin) {
        requireWalletOwnsTeacher(msg.sender, id);
        unregisterTeacher(id);
    }

    // SCENE
    function getClassroomGuid(
        int x,
        int y
    ) public view onlyRole(roleMap.teacher) returns (string memory) {
        // does the teacher have access to this classroom from the supplied coordinates?
        Teacher memory teacher = idsToObjects.teacher[msg.sender];
        uint256 callingLandId = landRegistry.encodeTokenId(x, y);
        bool teacherCanUseLand = false;
        string memory _classroomGuid;
        for (uint256 i = 0; i < teacher.classroomIds.length; i++) {
            Classroom memory currentClassroom = idsToObjects.classroom[
                teacher.classroomIds[i]
            ];
            for (uint256 j = 0; j < currentClassroom.landIds.length; j++) {
                uint256 currentLandId = currentClassroom.landIds[j];
                if (callingLandId == currentLandId) {
                    teacherCanUseLand = true;
                    _classroomGuid = currentClassroom.guid;
                    break;
                }
            }
            if (teacherCanUseLand) {
                break;
            }
        }
        require(
            teacherCanUseLand,
            "You are not authorised to use this classroom."
        );

        return _classroomGuid;
    }

    // private
    // land
    function areAnyLandIdsAssignedToClassroomAdmin(
        uint256[] memory landIds,
        address classroomAdminWallet
    ) private returns (bool) {
        // Relies on call being reverted to unregister
        // landIds.  Should only be used in a require.
        for (uint256 i = 0; i < landIds.length; i++) {
            if (registeredIds.landsRegisteredToClassroomAdminBool[landIds[i]]) {
                return true;
            }
            registerLandToClassroomAdmin(landIds[i], classroomAdminWallet);
        }
        return false;
    }

    function walletOwnsClassroom(
        address walletId,
        uint256 _classroomId
    ) private view returns (bool) {
        return
            idsToObjects.classroom[_classroomId].classroomAdminId == walletId;
    }

    function requireWalletOwnsTeacher(
        address walletId,
        address _teacherId
    ) private view {
        require(walletOwnsTeacher(walletId, _teacherId), ERR_OBJECT_ACCESS);
    }

    function walletOwnsTeacher(
        address walletId,
        address _teacherId
    ) private view returns (bool) {
        return
            arrayContainsAddress(
                idsToObjects.teacher[_teacherId].classroomAdminIds,
                walletId
            );
    }

    function checkLandIdsSuitableToBeAssignedToClassroom(
        address _walletAddress,
        uint256[] memory _landIds
    ) private view returns (bool) {
        for (uint256 i = 0; i < _landIds.length; i++) {
            uint256 landId = _landIds[i];
            // do the land ids exist?
            if (!registeredIds.landsRegisteredToClassroomAdminBool[landId]) {
                return false;
            }
            Land memory land = idsToObjects.land[landId];
            // are they yours?
            if (_walletAddress != land.classroomAdminId) {
                return false;
            }
            // are they assigned to any classrooms?
            if (land.classroomId != 0) {
                return false;
            }
        }
        return true;
    }

    function checkClassroomIdsSuitableToBeAssignedToTeacher(
        address classroomAdminWallet,
        uint256[] memory classroomIds
    ) private view returns (bool) {
        for (uint256 i = 0; i < classroomIds.length; i++) {
            uint256 classroomId = classroomIds[i];
            // do the classroom ids exist?
            if (!registeredIds.classroomBool[classroomId]) {
                return false;
            }
            Classroom memory classroom = idsToObjects.classroom[classroomId];
            // are they yours?
            if (classroomAdminWallet != classroom.classroomAdminId) {
                return false;
            }
        }
        return true;
    }

    function registerLandToClassroomAdmin(
        uint256 landId,
        address _classroomAdminId
    ) private {
        idsToObjects.land[landId] = Land({
            id: landId,
            classroomAdminId: _classroomAdminId,
            classroomId: 0
        });

        registeredIds.landsRegisteredToClassroomAdmin.push(landId);
        registeredIds.landsRegisteredToClassroomAdminBool[landId] = true;
    }

    function unregisterLandFromClassroomAdmin(uint256 landId) private {
        delete idsToObjects.land[landId];
        removeUintFromArrayMaintainOrder(
            registeredIds.landsRegisteredToClassroomAdmin,
            landId
        );
        delete registeredIds.landsRegisteredToClassroomAdminBool[landId];
    }

    function registerLandToClassroom(
        uint256 landId,
        uint256 _classroomId
    ) private {
        idsToObjects.land[landId].classroomId = _classroomId;
        registeredIds.landsRegisteredToClassroom.push(landId);
        registeredIds.landsRegisteredToClassroomBool[landId] = true;
    }

    function unregisterLandFromClassroom(uint256 landId) private {
        idsToObjects.land[landId].classroomId = 0;
        removeUintFromArrayMaintainOrder(
            registeredIds.landsRegisteredToClassroom,
            landId
        );
        delete registeredIds.landsRegisteredToClassroomBool[landId];
    }

    // classroomAdmin
    function registerClassroomAdmin(
        address _walletAddress,
        uint256[] memory landIds
    ) private {
        uint256[] memory emptyUintList;
        address[] memory emptyAddressList;
        int[][] memory _landCoordinates;

        idsToObjects.classroomAdmin[_walletAddress] = ClassroomAdmin({
            walletAddress: _walletAddress,
            landIds: landIds,
            landCoordinates: _landCoordinates,
            classroomIds: emptyUintList,
            teacherIds: emptyAddressList
        });
        toggleRole(_walletAddress, roleMap.classroomAdmin, true);
        // landIds automatically registered in require
    }

    function unregisterClassroomAdmin(address _walletAddress) private {
        ClassroomAdmin memory classroomAdmin = idsToObjects.classroomAdmin[
            _walletAddress
        ];

        for (uint256 i = 0; i < classroomAdmin.landIds.length; i++) {
            unregisterLandFromClassroomAdmin(classroomAdmin.landIds[i]);
        }

        // delete classrooms
        for (uint256 i = 0; i < classroomAdmin.classroomIds.length; i++) {
            unregisterClassroom(classroomAdmin.classroomIds[i]);
        }

        delete idsToObjects.classroomAdmin[_walletAddress];
        toggleRole(_walletAddress, roleMap.classroomAdmin, false);
    }

    function registerClassroom(
        uint256 _id,
        string memory _name,
        uint256[] memory _landIds,
        address _classroomAdminId,
        string memory _guid
    ) private {
        address[] memory emptyAddressList;
        int[][] memory emptyIntList;

        idsToObjects.classroom[_id] = Classroom({
            id: _id,
            name: _name,
            landIds: _landIds,
            landCoordinates: emptyIntList,
            classroomAdminId: _classroomAdminId,
            teacherIds: emptyAddressList,
            guid: _guid
        });
        registeredIds.classroom.push(_id);
        registeredIds.classroomBool[_id] = true;
        for (uint256 i = 0; i < _landIds.length; i++) {
            registerLandToClassroom(_landIds[i], _id);
        }
        idsToObjects.classroomAdmin[_classroomAdminId].classroomIds.push(_id);
    }

    function unregisterClassroom(uint256 _id) private {
        Classroom memory classroom = idsToObjects.classroom[_id];
        uint256[] memory _landIds = classroom.landIds;
        removeUintFromArrayMaintainOrder(registeredIds.classroom, _id);

        delete registeredIds.classroomBool[_id];
        for (uint256 i = 0; i < _landIds.length; i++) {
            unregisterLandFromClassroom(_landIds[i]);
        }
        removeUintFromArrayMaintainOrder(
            idsToObjects
                .classroomAdmin[classroom.classroomAdminId]
                .classroomIds,
            _id
        );

        // delete orphaned teachers
        for (uint256 i = 0; i < classroom.teacherIds.length; i++) {
            Teacher memory teacher = idsToObjects.teacher[
                classroom.teacherIds[i]
            ];
            if (teacher.classroomIds.length == 1) {
                unregisterTeacher(teacher.walletAddress);
            } else {
                // remove this classroom from the teacher
                uint256[] memory newClassroomIds = new uint256[](
                    teacher.classroomIds.length - 1
                );
                // build the new array
                // skip the classroom to be removed
                uint256 keyCounter = 0;
                for (uint256 j = 0; j < teacher.classroomIds.length; j++) {
                    if (teacher.classroomIds[j] != _id) {
                        newClassroomIds[j] = teacher.classroomIds[keyCounter];
                        keyCounter++;
                    }
                }
                _updateTeacher(teacher.walletAddress, newClassroomIds);
            }
        }

        delete idsToObjects.classroom[_id];
    }

    function registerTeacher(
        address _walletAddress,
        uint256[] memory _classroomIds
    ) private {
        // they could already be registered by another classroom admin
        // in which case we need to update them
        if (hasRole(roleMap.teacher, _walletAddress)) {
            // they are already registered with another CA
            idsToObjects.teacher[_walletAddress].classroomAdminIds.push(
                msg.sender
            );
        } else {
            address[] memory classroomAdminsWallets = new address[](1);
            classroomAdminsWallets[0] = msg.sender;
            idsToObjects.teacher[_walletAddress] = Teacher({
                walletAddress: _walletAddress,
                classroomIds: _classroomIds,
                classroomAdminIds: classroomAdminsWallets
            });
            toggleRole(
                _walletAddress,
                roleMap.teacher,
                true
            );
        }
        // associate with classrooms
        for (uint256 i = 0; i < _classroomIds.length; i++) {
            idsToObjects.classroom[_classroomIds[i]].teacherIds.push(
                _walletAddress
            );
        }
        idsToObjects.classroomAdmin[msg.sender].teacherIds.push(_walletAddress);
    }

    function unregisterTeacher(address _walletAddress) private {
        Teacher memory teacher = idsToObjects.teacher[_walletAddress];
        uint256 classroomAdminCount = teacher.classroomAdminIds.length;

        removeAddressFromArrayMaintainOrder(
            idsToObjects.classroomAdmin[msg.sender].teacherIds,
            _walletAddress
        );
        removeAddressFromArrayMaintainOrder(
            idsToObjects.teacher[_walletAddress].classroomAdminIds,
            msg.sender
        );

        if (classroomAdminCount == 1) {
            toggleRole(
                _walletAddress,
                roleMap.teacher,
                false
            );
            for (uint256 i = 0; i < teacher.classroomIds.length; i++) {
                removeAddressFromArrayMaintainOrder(
                    idsToObjects.classroom[teacher.classroomIds[i]].teacherIds,
                    _walletAddress
                );
            }
            delete idsToObjects.teacher[_walletAddress];
        }
    }

    function _updateTeacher(address id, uint256[] memory classroomIds) private {
        address walletAddress = idsToObjects.teacher[id].walletAddress;

        unregisterTeacher(id);
        registerTeacher(walletAddress, classroomIds);
    }

    // utility
    function removeAddressFromArrayMaintainOrder(
        address[] storage arr,
        address val
    ) private {
        for (uint256 i = 0; i < arr.length; i++) {
            if (val == arr[i]) {
                arr[i] = arr[arr.length - 1];
                arr.pop();
                break;
            }
        }
    }

    function removeUintFromArrayMaintainOrder(
        uint256[] storage arr,
        uint256 val
    ) private {
        for (uint256 i = 0; i < arr.length; i++) {
            if (val == arr[i]) {
                arr[i] = arr[arr.length - 1];
                arr.pop();
                break;
            }
        }
    }

    // function arrayContainsUint(
    //     uint256[] memory arr,
    //     uint256 val
    // ) private pure returns (bool) {
    //     for (uint256 i = 0; i < arr.length; i++) {
    //         if (arr[i] == val) {
    //             return true;
    //         }
    //     }
    //     return false;
    // }

    function arrayContainsAddress(
        address[] memory arr,
        address val
    ) private pure returns (bool) {
        for (uint256 i = 0; i < arr.length; i++) {
            if (arr[i] == val) {
                return true;
            }
        }
        return false;
    }

    function removeClassroomFromArrayMaintainOrder(
        Classroom[] storage arr,
        uint256 _classroomId
    ) private {
        for (uint256 i = 0; i < arr.length; i++) {
            if (_classroomId == arr[i].id) {
                arr[i] = arr[arr.length - 1];
                arr.pop();
                break;
            }
        }
    }

    function getCoordinatesFromLandIds(
        uint256[] memory landIds
    ) public view returns (int[][] memory) {
        int[][] memory rtn = new int[][](landIds.length);
        for (uint256 i = 0; i < landIds.length; i++) {
            (int x, int y) = landRegistry.decodeTokenId(landIds[i]);
            rtn[i] = new int[](2);
            rtn[i][0] = x;
            rtn[i][1] = y;
        }
        return rtn;
    }

    function getLandIdsFromCoordinates(
        int[][] memory coordinatePairs
    ) public view returns (uint256[] memory) {
        uint256[] memory landIds = new uint256[](coordinatePairs.length);
        for (uint256 i = 0; i < coordinatePairs.length; i++) {
            landIds[i] = landRegistry.encodeTokenId(
                coordinatePairs[i][0],
                coordinatePairs[i][1]
            );
        }
        return landIds;
    }

    function _isContract(address addr) internal view returns (bool) {
        uint size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }

    /*
     *    Grant or revoke role based on grant flag
     */
    function toggleRole(
        address beneficiary,
        RoleDetail storage roleDetail,
        bool grant
    ) private {
        if (grant) {
            roleDetail.addressArray.push(beneficiary);
            roleDetail.boolMapping[beneficiary] = true;
        } else {
            removeAddressFromArrayMaintainOrder(
                roleDetail.addressArray,
                beneficiary
            );
            delete roleDetail.boolMapping[beneficiary];
        }
    }

    function hasRole(
        RoleDetail storage roleDetail,
        address user
    ) internal view returns (bool) {
        return roleDetail.boolMapping[user];
    }

    modifier onlyRole(RoleDetail storage roleDetail) {
        require(
            roleDetail.boolMapping[msg.sender] == true,
            "You lack the appropriate role to call this function"
        );
        _;
    }

    modifier onlyOwner() {
        require(
            msg.sender == owner,
            "You lack the appropriate role to call this function"
        );
        _;
    }
}
