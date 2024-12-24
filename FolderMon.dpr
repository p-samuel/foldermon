program FolderMon;

{$APPTYPE CONSOLE}

uses
  Windows, SysUtils, Classes;

type
  FILE_NOTIFY_INFORMATION = record
    NextEntryOffset: DWORD;      // The offset in bytes from the beginning of this record to the next FILE_NOTIFY_INFORMATION record. If this is zero, there are no more records.
    Action: DWORD;               // The type of change that occurred. This can be one of several predefined constants indicating actions like file added, removed, modified, etc.
    FileNameLength: DWORD;       // The length, in bytes, of the file name string in the FileName array.
    FileName: array[0..0] of WideChar; // A variable-length array containing the file name that was affected by the change. The actual size of this array is determined by FileNameLength.
  end;
  PFILE_NOTIFY_INFORMATION = ^FILE_NOTIFY_INFORMATION; // A pointer type for the FILE_NOTIFY_INFORMATION record.
type
  TDirectoryMonitorThread = class(TThread)
  private
    FDirectory: string;
    FFileExtensions: TStringList;
  protected
    procedure Execute; override;
  public
    constructor Create(const Directory: string; FileExtensions: TStringList);
    destructor Destroy; override;
  end;

constructor TDirectoryMonitorThread.Create(const Directory: string; FileExtensions: TStringList);
begin
  inherited Create(False);
  FDirectory := Directory;
  FFileExtensions := TStringList.Create;
  FFileExtensions.Assign(FileExtensions);
  FreeOnTerminate := True;
end;

destructor TDirectoryMonitorThread.Destroy;
begin
  FFileExtensions.Free;
  inherited Destroy;
end;

procedure TDirectoryMonitorThread.Execute;
var
  DirectoryHandle: THandle;
  Buffer: array[0..1023] of Byte;
  BytesReturned: DWORD;
  Info: PFILE_NOTIFY_INFORMATION;
  Offset: DWORD;
  FileName: WideString;
  Extension: string;
begin
  DirectoryHandle := CreateFile(
    PChar(FDirectory),                      // Pointer to a null-terminated string that specifies the name of the directory to be monitored.
    FILE_LIST_DIRECTORY,                   // Desired access, specifying the access to the directory. FILE_LIST_DIRECTORY allows listing the contents of the directory.
    FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE, // Share mode, allowing subsequent open operations on the directory to request read, write, or delete access.
    nil,                                   // Pointer to a SECURITY_ATTRIBUTES structure. If nil, the handle cannot be inherited by child processes.
    OPEN_EXISTING,                         // Creation disposition, specifying that the directory must exist. If it doesn't, the function fails.
    FILE_FLAG_BACKUP_SEMANTICS or FILE_FLAG_OVERLAPPED, // Flags and attributes. FILE_FLAG_BACKUP_SEMANTICS allows opening a directory, and FILE_FLAG_OVERLAPPED enables asynchronous I/O.
    0                                      // Handle to a template file, which is ignored when opening a directory, so it's set to 0.
  );

  if DirectoryHandle = INVALID_HANDLE_VALUE then
  begin
    Writeln('Error opening directory: ', FDirectory);
    Exit;
  end;

  try
    Writeln('Monitoring ', FDirectory, ' for changes. Press Ctrl+C to stop.');
    while not Terminated do
    begin
      if ReadDirectoryChangesW(
        DirectoryHandle,          // Handle to the directory to be monitored. Obtained using CreateFile.
        @Buffer,                  // Pointer to the buffer that receives the read results.
        SizeOf(Buffer),           // Size of the buffer in bytes.
        True,                     // Boolean value indicating whether to monitor the directory and its subdirectories (True) or just the directory itself (False).
        FILE_NOTIFY_CHANGE_FILE_NAME or
        FILE_NOTIFY_CHANGE_DIR_NAME or
        FILE_NOTIFY_CHANGE_SIZE or
        FILE_NOTIFY_CHANGE_LAST_WRITE, // Filter specifying the types of changes to watch for: file name changes, directory name changes, size changes, and last write time changes.
        @BytesReturned,           // Pointer to a variable that receives the number of bytes returned.
        nil,                      // Pointer to an OVERLAPPED structure (used for asynchronous operations). Here, it's set to nil for synchronous operation.
        nil                       // Reserved; must be NULL. Used for asynchronous operations with a completion routine.
      ) then
      begin
        Offset := 0;
        repeat
          Info := PFILE_NOTIFY_INFORMATION(@Buffer[Offset]);
          SetString(FileName, Info^.FileName, Info^.FileNameLength div SizeOf(WideChar));
          Extension := ExtractFileExt(FileName);

          // Determine the color based on the action
          case Info^.Action of
            FILE_ACTION_ADDED:
              if (FFileExtensions.IndexOf(Extension) >= 0) then
                Writeln(FormatDateTime('hh:nn:ss.zzzz', Now), #27'[32m[CREATE    ]: ', FileName, #27'[0m') // Blue for file creation
              else
                Writeln(FormatDateTime('hh:nn:ss.zzzz', Now), '[CREATE    ]: ', FileName);
            FILE_ACTION_REMOVED:
              if (FFileExtensions.IndexOf(Extension) >= 0) then
                Writeln(FormatDateTime('hh:nn:ss.zzzz', Now), #27'[31m[DELETE    ]: ', FileName, #27'[0m') // Red for file deletion
              else
                Writeln(FormatDateTime('hh:nn:ss.zzzz', Now), '[DELETE    ]: ', FileName);
            FILE_ACTION_MODIFIED:
              if (FFileExtensions.IndexOf(Extension) >= 0) then
                Writeln(FormatDateTime('hh:nn:ss.zzzz', Now), #27'[33m[EDIT      ]: ', FileName, #27'[0m') // Green for file modification
              else
                Writeln(FormatDateTime('hh:nn:ss.zzzz', Now), '[EDIT      ]: ', FileName);
            FILE_ACTION_RENAMED_OLD_NAME:
              if (FFileExtensions.IndexOf(Extension) >= 0) then
                Writeln(FormatDateTime('hh:nn:ss.zzzz', Now), #27'[34m[RENAME_OLD]: ', FileName, #27'[0m')
              else
                Writeln(FormatDateTime('hh:nn:ss.zzzz', Now), '[RENAME_OLD]: ', FileName);
            FILE_ACTION_RENAMED_NEW_NAME:
               if (FFileExtensions.IndexOf(Extension) >= 0) then
                Writeln(FormatDateTime('hh:nn:ss.zzzz', Now), #27'[35m[RENAME_NEW]: ', FileName, #27'[0m')
               else
                Writeln(FormatDateTime('hh:nn:ss.zzzz', Now), '[RENAME_NEW]: ', FileName);
          else
            Writeln(FormatDateTime('hh:nn:ss.zzzz', Now), '[??????????]', FDirectory, ': ', FileName);
          end;

          Offset := Offset + Info^.NextEntryOffset;
        until Info^.NextEntryOffset = 0;
      end
      else
      begin
        Writeln('Error reading directory changes in ', FDirectory);
        Break;
      end;
    end;
  finally
    CloseHandle(DirectoryHandle);
  end;
end;

var
  Directories, FileExtensions: TStringList;
  Directory, Input: string;
  UseFilters: Boolean;
begin
  Directories := TStringList.Create;
  FileExtensions := TStringList.Create;
  try
    Writeln('Enter directories to monitor (one per line). Enter a blank line to finish:');
    repeat
      Readln(Directory);
      if Directory <> '' then
      begin
        if DirectoryExists(Directory) then
          Directories.Add(Directory)
        else
          Writeln('Directory does not exist: ', Directory);
      end;
    until Directory = '';

    if Directories.Count = 0 then
    begin
      Writeln('No valid directories entered. Exiting.');
      Exit;
    end;

    Writeln('Do you want to add file and directory filters? (yes/no)');
    Readln(Input);
    UseFilters := LowerCase(Input) = 'yes';

    if UseFilters then
    begin
      Writeln('Enter file extensions to highlight (e.g., .pas, .txt), one per line. Enter a blank line to finish:');
      repeat
        Readln(Input);
        if Input <> '' then
          FileExtensions.Add(LowerCase(Input));
      until Input = '';
    end;

    for Directory in Directories do
    begin
      TDirectoryMonitorThread.Create(Directory, FileExtensions);
    end;

    Writeln('Press Ctrl+C to stop.');
    while True do
    begin
      Sleep(1000);
    end;
  finally
    Directories.Free;
    FileExtensions.Free;
  end;
end.

