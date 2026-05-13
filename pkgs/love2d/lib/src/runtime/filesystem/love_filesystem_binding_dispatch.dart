part of 'love_filesystem_bindings.dart';

/// Binds `love.filesystem.append`.
LoveApiImplementation _bindFilesystemAppend(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).append();

/// Binds `love.filesystem.areSymlinksEnabled`.
LoveApiImplementation _bindFilesystemAreSymlinksEnabled(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).areSymlinksEnabled();

/// Binds `love.filesystem.createDirectory`.
LoveApiImplementation _bindFilesystemCreateDirectory(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).createDirectory();

/// Binds `love.filesystem.getAppdataDirectory`.
LoveApiImplementation _bindFilesystemGetAppdataDirectory(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).getAppdataDirectory();

/// Binds `love.filesystem.getCRequirePath`.
LoveApiImplementation _bindFilesystemGetCRequirePath(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).getCRequirePath();

/// Binds `love.filesystem.getDirectoryItems`.
LoveApiImplementation _bindFilesystemGetDirectoryItems(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).getDirectoryItems();

/// Binds `love.filesystem.getIdentity`.
LoveApiImplementation _bindFilesystemGetIdentity(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).getIdentity();

/// Binds `love.filesystem.getInfo`.
LoveApiImplementation _bindFilesystemGetInfo(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).getInfo();

/// Binds `love.filesystem.getRealDirectory`.
LoveApiImplementation _bindFilesystemGetRealDirectory(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).getRealDirectory();

/// Binds `love.filesystem.getRequirePath`.
LoveApiImplementation _bindFilesystemGetRequirePath(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).getRequirePath();

/// Binds `love.filesystem.getSaveDirectory`.
LoveApiImplementation _bindFilesystemGetSaveDirectory(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).getSaveDirectory();

/// Binds `love.filesystem.getSource`.
LoveApiImplementation _bindFilesystemGetSource(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).getSource();

/// Binds `love.filesystem.getSourceBaseDirectory`.
LoveApiImplementation _bindFilesystemGetSourceBaseDirectory(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).getSourceBaseDirectory();

/// Binds `love.filesystem.getUserDirectory`.
LoveApiImplementation _bindFilesystemGetUserDirectory(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).getUserDirectory();

/// Binds `love.filesystem.getWorkingDirectory`.
LoveApiImplementation _bindFilesystemGetWorkingDirectory(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).getWorkingDirectory();

/// Binds `love.filesystem.init`.
LoveApiImplementation _bindFilesystemInit(LibraryRegistrationContext context) =>
    _LoveFilesystemBindings(context).init();

/// Binds `love.filesystem.isFused`.
LoveApiImplementation _bindFilesystemIsFused(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).isFused();

/// Binds `love.filesystem.lines`.
LoveApiImplementation _bindFilesystemLines(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).lines();

/// Binds `love.filesystem.load`.
LoveApiImplementation _bindFilesystemLoad(LibraryRegistrationContext context) =>
    _LoveFilesystemBindings(context).load();

/// Binds `love.filesystem.mount`.
LoveApiImplementation _bindFilesystemMount(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).mount();

/// Binds `love.filesystem.newFile`.
LoveApiImplementation _bindFilesystemNewFile(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).newFile();

/// Binds `love.filesystem.newFileData`.
LoveApiImplementation _bindFilesystemNewFileData(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).newFileData();

/// Binds `love.filesystem.read`.
LoveApiImplementation _bindFilesystemRead(LibraryRegistrationContext context) =>
    _LoveFilesystemBindings(context).read();

/// Binds `love.filesystem.remove`.
LoveApiImplementation _bindFilesystemRemove(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).remove();

/// Binds `love.filesystem.setCRequirePath`.
LoveApiImplementation _bindFilesystemSetCRequirePath(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).setCRequirePath();

/// Binds `love.filesystem.setIdentity`.
LoveApiImplementation _bindFilesystemSetIdentity(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).setIdentity();

/// Binds `love.filesystem.setRequirePath`.
LoveApiImplementation _bindFilesystemSetRequirePath(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).setRequirePath();

/// Binds `love.filesystem.setSource`.
LoveApiImplementation _bindFilesystemSetSource(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).setSource();

/// Binds `love.filesystem.setSymlinksEnabled`.
LoveApiImplementation _bindFilesystemSetSymlinksEnabled(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).setSymlinksEnabled();

/// Binds `love.filesystem.unmount`.
LoveApiImplementation _bindFilesystemUnmount(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).unmount();

/// Binds `love.filesystem.write`.
LoveApiImplementation _bindFilesystemWrite(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).write();

/// Binds `File:close`.
LoveApiImplementation _bindFileClose(LibraryRegistrationContext context) =>
    _LoveFilesystemBindings(context).fileClose();

/// Binds `File:flush`.
LoveApiImplementation _bindFileFlush(LibraryRegistrationContext context) =>
    _LoveFilesystemBindings(context).fileFlush();

/// Binds `File:getBuffer`.
LoveApiImplementation _bindFileGetBuffer(LibraryRegistrationContext context) =>
    _LoveFilesystemBindings(context).fileGetBuffer();

/// Binds `File:getFilename`.
LoveApiImplementation _bindFileGetFilename(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).fileGetFilename();

/// Binds `File:getExtension`.
LoveApiImplementation _bindFileGetExtension(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).fileGetExtension();

/// Binds `File:getMode`.
LoveApiImplementation _bindFileGetMode(LibraryRegistrationContext context) =>
    _LoveFilesystemBindings(context).fileGetMode();

/// Binds `File:getSize`.
LoveApiImplementation _bindFileGetSize(LibraryRegistrationContext context) =>
    _LoveFilesystemBindings(context).fileGetSize();

/// Binds `File:isEOF`.
LoveApiImplementation _bindFileIsEOF(LibraryRegistrationContext context) =>
    _LoveFilesystemBindings(context).fileIsEOF();

/// Binds `File:isOpen`.
LoveApiImplementation _bindFileIsOpen(LibraryRegistrationContext context) =>
    _LoveFilesystemBindings(context).fileIsOpen();

/// Binds `File:lines`.
LoveApiImplementation _bindFileLines(LibraryRegistrationContext context) =>
    _LoveFilesystemBindings(context).fileLines();

/// Binds `File:open`.
LoveApiImplementation _bindFileOpen(LibraryRegistrationContext context) =>
    _LoveFilesystemBindings(context).fileOpen();

/// Binds `File:read`.
LoveApiImplementation _bindFileRead(LibraryRegistrationContext context) =>
    _LoveFilesystemBindings(context).fileRead();

/// Binds `File:seek`.
LoveApiImplementation _bindFileSeek(LibraryRegistrationContext context) =>
    _LoveFilesystemBindings(context).fileSeek();

/// Binds `File:setBuffer`.
LoveApiImplementation _bindFileSetBuffer(LibraryRegistrationContext context) =>
    _LoveFilesystemBindings(context).fileSetBuffer();

/// Binds `File:tell`.
LoveApiImplementation _bindFileTell(LibraryRegistrationContext context) =>
    _LoveFilesystemBindings(context).fileTell();

/// Binds `File:write`.
LoveApiImplementation _bindFileWrite(LibraryRegistrationContext context) =>
    _LoveFilesystemBindings(context).fileWrite();

/// Binds `FileData:clone`.
LoveApiImplementation _bindFileDataClone(LibraryRegistrationContext context) =>
    _LoveFilesystemBindings(context).fileDataClone();

/// Binds `FileData:getExtension`.
LoveApiImplementation _bindFileDataGetExtension(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).fileDataGetExtension();

/// Binds `FileData:getFilename`.
LoveApiImplementation _bindFileDataGetFilename(
  LibraryRegistrationContext context,
) => _LoveFilesystemBindings(context).fileDataGetFilename();

/// Binds `Data:getSize`.
LoveApiImplementation _bindDataGetSize(LibraryRegistrationContext context) =>
    _LoveFilesystemBindings(context).dataGetSize();

/// Binds `Data:getString`.
LoveApiImplementation _bindDataGetString(LibraryRegistrationContext context) =>
    _LoveFilesystemBindings(context).dataGetString();

/// Binds `Object:release`.
LoveApiImplementation _bindObjectRelease(LibraryRegistrationContext context) =>
    _LoveFilesystemBindings(context).objectRelease();

/// Binds `Object:type`.
LoveApiImplementation _bindObjectType(LibraryRegistrationContext context) =>
    _LoveFilesystemBindings(context).objectType();

/// Binds `Object:typeOf`.
LoveApiImplementation _bindObjectTypeOf(LibraryRegistrationContext context) =>
    _LoveFilesystemBindings(context).objectTypeOf();
