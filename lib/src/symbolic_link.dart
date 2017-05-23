import 'dart:io';

class SyncedFSNode {
  final String syncName;
  final String target;

  SyncedFSNode(String target, String syncName) :
      this.target = target,
      this.syncName = syncName;
  SyncedFSNode.same(String link) :
      this(link, link);

  factory SyncedFSNode.fromPrimitive(dynamic item) {
    if (item is Map) {
      if (item.keys.length > 1 || item.keys.isEmpty) {
        throw "Invalid number of keys for map $item";
      }

      var k = item.keys.first as String;
      return new SyncedFSNode(k, item[k]);
    } else if (item is String) {
      return new SyncedFSNode.same(item);
    }

    throw "Invalid fs node specifier ${item}";
  }

  String _workingDir;
  Uri _targetUri;
  Uri _syncUri;
  void _initURIs(String dotfilesPath, String installPath) {
    _workingDir = new Directory('.').resolveSymbolicLinksSync();
    _targetUri = new Uri.file("$_workingDir/${dotfilesPath}/${target}");
    _targetUri = _fileUriNormalize(_targetUri);
    _syncUri = new Uri.file("${installPath}/${syncName}");
  }

  void link(String dotfilesPath, String installPath, dryRun) {
    _initURIs(dotfilesPath, installPath);

    var link = new Link.fromUri(_syncUri);
    var linkType = _fsTypeSync(_syncUri);

    if (linkType != FileSystemEntityType.NOT_FOUND &&
        linkType != FileSystemEntityType.LINK || _isLinkValid(link)) {
      var currentTarget = new Uri.file(link.resolveSymbolicLinksSync());
      currentTarget = _fileUriNormalize(currentTarget);

      if (currentTarget != _targetUri) {
        _backupTarget(currentTarget, _targetUri, dryRun);
      } else {
        if (dryRun) print("Skipping ${link.path}. Already configured");
        return;
      }
    }

    if (FileStat.statSync(_targetUri.toFilePath()).type ==
        FileSystemEntityType.NOT_FOUND && !dryRun) {
       print("Skipping ${link.path}. Link and target don't exist");
       return;
    }

    _forceCreateLink(link, _syncUri, linkType, _targetUri, dryRun);
  }

  void cp(String dotfilesPath, String installPath, dryRun) {
    _initURIs(dotfilesPath, installPath);

    var existingF = new File.fromUri(_syncUri);
    var backupF = new File(_targetUri.toFilePath() + ".bak");
    if (existingF.existsSync()) {
      if (dryRun) print("Backing up ${_syncUri.toFilePath()} to ${backupF.path}");
      else {
        existingF.copySync("${backupF.path}");
        _deletePath(_syncUri, _fsTypeSync(_syncUri));
      }
    }

    if (dryRun) print("Copying ${_targetUri.toFilePath()} to ${_syncUri.toFilePath()}");
    else {
      new File.fromUri(_targetUri).copySync(_syncUri.toFilePath());
      backupF.renameSync(_targetUri.toFilePath());
    }
  }

  @override
  String toString() => "$syncName -> $target";

  void _backupTarget(Uri currentTarget, Uri expectedTarget, bool dryRun) {
    var currentTargetType = _fsTypeSync(currentTarget);
    if (currentTargetType == FileSystemEntityType.FILE) {
      if (dryRun) print("Copy ${currentTarget.toFilePath()} to ${expectedTarget.toFilePath()}");
      else _copy(currentTarget, expectedTarget);
    } else if (currentTargetType == FileSystemEntityType.DIRECTORY) {
      if (dryRun) print("Copy recursively ${currentTarget.toFilePath()} to "
                        "${expectedTarget.toFilePath()}");
      else _copyDir(currentTarget, expectedTarget);
    }
  }

  void _copy(Uri fromUri, Uri toUri) {
    var from = new File.fromUri(fromUri);
    var to = new File.fromUri(toUri);
    if (!to.existsSync()) to.createSync(recursive: true);

    from.copySync(to.path);
  }

  void _copyDir(Uri fromUri, Uri toUri) {
    var to = new Directory.fromUri(toUri);
    if (!to.existsSync()) to.createSync(recursive: true);

    Process.runSync('cp', ['--recursive', '${fromUri.toFilePath()}/.', '${toUri.toFilePath()}']);
  }

  void _deletePath(Uri uri, FileSystemEntityType pathType) {
    switch (pathType) {
      case FileSystemEntityType.LINK:
        new Link.fromUri(uri).deleteSync();
        break;
      case FileSystemEntityType.FILE:
        new File.fromUri(uri).deleteSync();
        break;
      case FileSystemEntityType.DIRECTORY:
        new Directory.fromUri(uri).deleteSync(recursive: true);
        break;
    }
  }

  bool _isLinkValid(Link link) {
    try {
      link.resolveSymbolicLinksSync();
      return true;
    } on FileSystemException catch (e) {
      if (e.osError.errorCode == 2) {
        return false;
      } else rethrow;
    }
  }

  Uri _fileUriNormalize(Uri f) {
    var norm = f.normalizePath();
    if (norm.path.endsWith("/")) {
      norm = new Uri.file(norm.path.substring(0, norm.path.length - 1));
    }

    return norm;
  }

  void _forceCreateLink(Link link, Uri linkUri, FileSystemEntityType linkType,
                        Uri targetUri, bool dryRun) {
    try {
      if (linkType != FileSystemEntityType.NOT_FOUND) {
        if (dryRun) print("Delete ${link.path}");
        else _deletePath(linkUri, linkType);
      }

      if (dryRun) print("Link ${link.path} to ${targetUri.toFilePath()}");
      else link.createSync(targetUri.toFilePath(), recursive: true);
    } on FileSystemException catch (e) {
      _onFSException(e, linkUri, targetUri);
    }
  }

  FileSystemEntityType _fsTypeSync(Uri uri) {
    var type = FileStat.statSync(uri.toFilePath()).type;
    // Now manually check if it's a link
    if (FileSystemEntity.isLinkSync(uri.toFilePath())) {
      type = FileSystemEntityType.LINK;
    }

    return type;
  }

  void _onFSException(FileSystemException e, Uri link, Uri target) {
    if (e.osError.errorCode == 13) {
      print("Permission denied. Cannot link ${link.toFilePath()} to ${target.toFilePath()}");
    } else {
      throw e;
    }
  }
}
