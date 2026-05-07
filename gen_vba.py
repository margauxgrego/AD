import struct, base64, sys

SECTOR_SIZE = 512
MINI_SECTOR_SIZE = 64
MINI_CUTOFF = 4096
ENDOFCHAIN = 0xFFFFFFFE
FREESECT = 0xFFFFFFFF
FATSECT = 0xFFFFFFFD
NOSTREAM = 0xFFFFFFFF
RED = 0; BLACK = 1

def pad_sector(data, size=SECTOR_SIZE):
    n = len(data) % size
    return data + bytes(size - n) if n else data

def sectors_for(size, sec_size=SECTOR_SIZE):
    return max(1, (size + sec_size - 1) // sec_size)

def mini_sectors_for(size):
    return max(1, (size + MINI_SECTOR_SIZE - 1) // MINI_SECTOR_SIZE)

# MS-OVBA: raw (uncompressed) compression
def ovba_compress(data):
    if isinstance(data, str): data = data.encode('latin-1')
    out = bytearray([0x01])
    i = 0
    while i < len(data):
        chunk = bytes(data[i:i+4096]).ljust(4096, b'\x00')
        out += struct.pack('<H', 0x0FFF) + chunk
        i += 4096
    return bytes(out)

def rec(id, data=b''):
    return struct.pack('<HI', id, len(data)) + data

def build_dir_stream():
    mn = b'ThisWorkbook'
    mn_u = 'ThisWorkbook'.encode('utf-16-le')
    s = b''
    s += rec(0x0001, struct.pack('<I', 0x01))       # SYSKIND Win32
    s += rec(0x0002, struct.pack('<I', 0x0409))      # LCID
    s += rec(0x0014, struct.pack('<I', 0x0409))      # LCIDINVOKE
    s += rec(0x0003, struct.pack('<H', 1252))         # CODEPAGE
    s += rec(0x0004, b'VBAProject')                  # PROJECTNAME
    s += rec(0x0005, b'')                            # DOCSTRING
    s += rec(0x0040, b'')                            # DOCSTRINGUNICODE
    s += rec(0x0006, b'')                            # HELPFILE1
    s += rec(0x003D, b'')                            # HELPFILE2
    s += rec(0x0007, struct.pack('<I', 0))           # HELPCONTEXT
    s += rec(0x0008, struct.pack('<I', 0))           # LIBFLAGS
    s += rec(0x0009, struct.pack('<IH', 0x61, 0x000E))  # VERSION major=97 minor=14
    s += rec(0x000C, b'')                            # CONSTANTS
    s += rec(0x003C, b'')                            # CONSTANTSUNICODE
    # References: none (Excel provides its own context)
    s += rec(0x000F, struct.pack('<I', 1))           # PROJECTMODULES count=1
    s += rec(0x0013, struct.pack('<H', 0xFFFF))      # PROJECTCOOKIE
    # Module: ThisWorkbook (class module)
    s += rec(0x0019, mn)                             # MODULENAME
    s += rec(0x0047, mn_u)                           # MODULENAMEUNICODE
    s += rec(0x001A, mn)                             # MODULESTREAMNAME
    s += rec(0x0032, mn_u)                           # MODULESTREAMNAMEUNICODE
    s += rec(0x001C, b'')                            # MODULEDOCSTRING
    s += rec(0x0048, b'')                            # MODULEDOCSTRINGUNICODE
    s += rec(0x0031, struct.pack('<I', 0))           # MODULEOFFSET=0
    s += rec(0x001E, struct.pack('<I', 0))           # MODULEHELPCONTEXT
    s += rec(0x002C, struct.pack('<H', 0xFFFF))      # MODULECOOKIE
    s += rec(0x0022, b'')                            # MODULETYPE class
    s += rec(0x002B, b'')                            # MODULE terminator
    s += rec(0x0010, b'')                            # PROJECTMODULES terminator
    return s

VBA_SOURCE = b'Attribute VB_Name = "ThisWorkbook"\r\nPrivate Sub Workbook_Open()\r\n    Dim ws As Worksheet\r\n    For Each ws In ThisWorkbook.Worksheets\r\n        If ws.Name Like "D*" And IsNumeric(Mid(ws.Name, 2)) Then\r\n            ws.Visible = xlSheetHidden\r\n        End If\r\n    Next ws\r\nEnd Sub\r\n\r\nPrivate Sub Workbook_SheetActivate(ByVal Sh As Object)\r\n    If Sh.Name = "TCD" Then\r\n        Dim ws As Worksheet\r\n        For Each ws In ThisWorkbook.Worksheets\r\n            If ws.Name Like "D*" And IsNumeric(Mid(ws.Name, 2)) Then\r\n                ws.Visible = xlSheetHidden\r\n            End If\r\n        Next ws\r\n    End If\r\nEnd Sub\r\n\r\nPrivate Sub Workbook_SheetFollowHyperlink(ByVal Sh As Object, ByVal Target As Hyperlink)\r\n    Dim addr As String, shName As String, bang As Integer\r\n    addr = Target.SubAddress\r\n    If Left(addr, 1) = Chr(39) Then\r\n        shName = Mid(addr, 2, InStr(2, addr, Chr(39)) - 2)\r\n    Else\r\n        bang = InStr(addr, "!")\r\n        If bang > 0 Then shName = Left(addr, bang - 1)\r\n    End If\r\n    If shName Like "D*" And IsNumeric(Mid(shName, 2)) Then\r\n        Dim ws As Worksheet\r\n        For Each ws In ThisWorkbook.Worksheets\r\n            If ws.Name Like "D*" And IsNumeric(Mid(ws.Name, 2)) Then ws.Visible = xlSheetHidden\r\n        Next ws\r\n        ThisWorkbook.Worksheets(shName).Visible = xlSheetVisible\r\n        ThisWorkbook.Worksheets(shName).Activate\r\n    End If\r\nEnd Sub\r\n'

def build_project():
    return b'ID="{00000000-0000-0000-0000-000000000000}"\r\nDocument=ThisWorkbook/&H00000000\r\nName="VBAProject"\r\nHelpContextID="0"\r\nVersionCompatible32="393222000"\r\nCMG=""\r\nDPB=""\r\nGC=""\r\n'

def build_projectwm():
    n = b'ThisWorkbook'
    return n + b'\x00' + n.decode().encode('utf-16-le') + b'\x00\x00' + b'\x00\x00'

def build_vba_project():
    # Minimal _VBA_PROJECT: no compiled p-code (Excel will recompile from source)
    return bytes(20)

def dir_entry(name, obj_type, color, left, right, child, start, size):
    e = bytearray(128)
    if name:
        nb = name.encode('utf-16-le')[:62]
        e[:len(nb)] = nb
        struct.pack_into('<H', e, 64, len(nb) + 2)
    e[66] = obj_type; e[67] = color
    struct.pack_into('<I', e, 68, left)
    struct.pack_into('<I', e, 72, right)
    struct.pack_into('<I', e, 76, child)
    struct.pack_into('<I', e, 116, start)
    struct.pack_into('<I', e, 120, size)
    return bytes(e)

def build():
    # Prepare stream data
    vba_proj = build_vba_project()          # mini stream
    project = build_project()               # mini stream
    projectwm = build_projectwm()           # mini stream
    dir_stream = ovba_compress(build_dir_stream())   # regular
    twb_stream = ovba_compress(VBA_SOURCE)           # regular

    # Mini stream layout (64-byte sectors)
    mini_streams = [vba_proj, project, projectwm]
    mini_starts = []
    ms = 0
    mini_data = bytearray()
    for d in mini_streams:
        mini_starts.append(ms)
        n = mini_sectors_for(len(d))
        mini_data.extend(d)
        mini_data.extend(bytes(n * MINI_SECTOR_SIZE - len(d)))
        ms += n

    total_mini_secs = ms
    mini_data_padded = bytes(mini_data).ljust(sectors_for(len(mini_data)) * SECTOR_SIZE, b'\x00')

    # Sector layout
    # 0: FAT, 1: Dir[0], 2: Dir[1], 3: MiniFAT, 4: mini-stream container
    # 5..: dir_stream sectors, then twb_stream sectors
    dir_sec_count = sectors_for(len(dir_stream))
    twb_sec_count = sectors_for(len(twb_stream))
    mini_cont_sec_count = sectors_for(len(mini_data_padded))

    fat_sec = 0
    dir0_sec = 1; dir1_sec = 2
    minifat_sec = 3
    mini_cont_start = 4
    dir_stream_start = mini_cont_start + mini_cont_sec_count
    twb_stream_start = dir_stream_start + dir_sec_count

    # FAT
    fat = [FREESECT] * 128
    fat[fat_sec] = FATSECT
    fat[dir0_sec] = dir1_sec; fat[dir1_sec] = ENDOFCHAIN
    fat[minifat_sec] = ENDOFCHAIN
    for i in range(mini_cont_sec_count):
        fat[mini_cont_start + i] = mini_cont_start + i + 1
    fat[mini_cont_start + mini_cont_sec_count - 1] = ENDOFCHAIN
    for i in range(dir_sec_count):
        fat[dir_stream_start + i] = dir_stream_start + i + 1
    fat[dir_stream_start + dir_sec_count - 1] = ENDOFCHAIN
    for i in range(twb_sec_count):
        fat[twb_stream_start + i] = twb_stream_start + i + 1
    fat[twb_stream_start + twb_sec_count - 1] = ENDOFCHAIN
    fat_data = struct.pack('<128I', *fat)

    # Mini FAT
    mini_fat = [FREESECT] * 128
    ms_cursor = 0
    for d in mini_streams:
        n = mini_sectors_for(len(d))
        for i in range(n): mini_fat[ms_cursor + i] = ms_cursor + i + 1
        mini_fat[ms_cursor + n - 1] = ENDOFCHAIN
        ms_cursor += n
    mini_fat_data = struct.pack('<128I', *mini_fat)

    # Directory entries (8 entries = 2 sectors of 4 entries each)
    # IDs: 0=Root 1=VBA 2=_VBA_PROJECT 3=dir 4=ThisWorkbook 5=PROJECT 6=PROJECTwm 7=unused
    # Root children (alphabetical case-insensitive): PROJECT < PROJECTwm < VBA
    #   tree: PROJECTwm(6) BLACK, left=PROJECT(5) RED, right=VBA(1) RED
    # VBA children: dir < ThisWorkbook < _VBA_PROJECT (D < T < _)
    #   tree: ThisWorkbook(4) BLACK, left=dir(3) RED, right=_VBA_PROJECT(2) RED

    root_e = bytearray(dir_entry('Root Entry', 5, BLACK, NOSTREAM, NOSTREAM, 6, mini_cont_start, len(mini_data_padded)))
    entries = [
        bytes(root_e),
        dir_entry('VBA', 1, RED, NOSTREAM, NOSTREAM, 4, ENDOFCHAIN, 0),
        dir_entry('_VBA_PROJECT', 2, RED, NOSTREAM, NOSTREAM, NOSTREAM, mini_starts[0], len(vba_proj)),
        dir_entry('dir', 2, RED, NOSTREAM, NOSTREAM, NOSTREAM, dir_stream_start, len(dir_stream)),
        dir_entry('ThisWorkbook', 2, BLACK, 3, 2, NOSTREAM, twb_stream_start, len(twb_stream)),
        dir_entry('PROJECT', 2, RED, NOSTREAM, NOSTREAM, NOSTREAM, mini_starts[1], len(project)),
        dir_entry('PROJECTwm', 2, BLACK, 5, 1, NOSTREAM, mini_starts[2], len(projectwm)),
        bytes(128),  # unused slot
    ]
    dir_sectors_data = b''.join(entries)  # 1024 bytes = 2 sectors

    # CFB Header
    hdr = bytearray(512)
    hdr[0:8] = b'\xD0\xCF\x11\xE0\xA1\xB1\x1A\xE1'
    struct.pack_into('<H', hdr, 24, 0x003E)   # minor version
    struct.pack_into('<H', hdr, 26, 0x0003)   # major version (512-byte sectors)
    struct.pack_into('<H', hdr, 28, 0xFFFE)   # byte order LE
    struct.pack_into('<H', hdr, 30, 0x0009)   # sector size = 2^9 = 512
    struct.pack_into('<H', hdr, 32, 0x0006)   # mini sector size = 2^6 = 64
    struct.pack_into('<I', hdr, 44, 1)         # total FAT sectors
    struct.pack_into('<I', hdr, 48, dir0_sec)  # first directory sector
    struct.pack_into('<I', hdr, 56, 0x1000)   # mini stream cutoff
    struct.pack_into('<I', hdr, 60, minifat_sec)  # first mini FAT sector
    struct.pack_into('<I', hdr, 64, 1)         # total mini FAT sectors
    struct.pack_into('<I', hdr, 68, FREESECT)  # no DIFAT
    struct.pack_into('<I', hdr, 72, 0)         # total DIFAT sectors
    struct.pack_into('<I', hdr, 76, fat_sec)   # DIFAT[0] = FAT sector
    for i in range(108):
        struct.pack_into('<I', hdr, 80 + i*4, FREESECT)

    # Assemble
    out = bytes(hdr) + fat_data + dir_sectors_data + mini_fat_data + mini_data_padded
    out += bytes(dir_stream).ljust(dir_sec_count * SECTOR_SIZE, b'\x00')
    out += bytes(twb_stream).ljust(twb_sec_count * SECTOR_SIZE, b'\x00')
    return out

if __name__ == '__main__':
    data = build()
    print(base64.b64encode(data).decode())
    sys.stderr.write(f"vbaProject.bin size: {len(data)} bytes\n")
