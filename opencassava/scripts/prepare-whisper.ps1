$ErrorActionPreference = "Stop"

$workspaceRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$buildRoot = Join-Path $workspaceRoot ".build"
$whisperRoot = Join-Path $buildRoot "whisper-rs"
$repoUrls = @(
  "https://codeberg.org/tazz4843/whisper-rs.git",
  "https://github.com/tazz4843/whisper-rs.git"
)
$repoCommit = "b202069aa891d8243206f89599c04f0e8e6a3d27"
$cacheStamp = Join-Path $whisperRoot ".openoats-patched-commit"

function Remove-WhisperRoot {
  if (Test-Path $whisperRoot) {
    Remove-Item -Recurse -Force $whisperRoot
  }
}

function Invoke-WhisperClone {
  $failures = New-Object System.Collections.Generic.List[string]

  foreach ($repoUrl in $repoUrls) {
    Remove-WhisperRoot
    Write-Host "Cloning whisper-rs from $repoUrl"

    & git clone $repoUrl $whisperRoot
    if ($LASTEXITCODE -ne 0) {
      $failures.Add("${repoUrl}: git clone failed with exit code $LASTEXITCODE")
      continue
    }

    & git -C $whisperRoot checkout $repoCommit
    if ($LASTEXITCODE -ne 0) {
      $failures.Add("${repoUrl}: git checkout $repoCommit failed with exit code $LASTEXITCODE")
      continue
    }

    & git -C $whisperRoot submodule update --init --recursive
    if ($LASTEXITCODE -ne 0) {
      $failures.Add("${repoUrl}: git submodule update failed with exit code $LASTEXITCODE")
      continue
    }

    return
  }

  Remove-WhisperRoot
  throw "Failed to prepare whisper-rs from all configured remotes.`n$($failures -join "`n")"
}

New-Item -ItemType Directory -Force -Path $buildRoot | Out-Null

if (-not (Test-Path $whisperRoot)) {
  Invoke-WhisperClone
} elseif (Test-Path $cacheStamp) {
  $cachedCommit = (Get-Content $cacheStamp -Raw).Trim()
  if ($cachedCommit -ne $repoCommit) {
    Invoke-WhisperClone
  }
} elseif (-not (Test-Path (Join-Path $whisperRoot ".git"))) {
  Invoke-WhisperClone
}

$sysRoot = Join-Path $whisperRoot "sys"
$sysBuild = Join-Path $sysRoot "build.rs"
$sysBindings = Join-Path $sysRoot "src" "bindings.rs"
$commonLogging = Join-Path $whisperRoot "src" "common_logging.rs"
$grammar = Join-Path $whisperRoot "src" "whisper_grammar.rs"

if (
  -not (Test-Path $sysBuild) -or
  -not (Test-Path $sysBindings) -or
  -not (Test-Path $commonLogging) -or
  -not (Test-Path $grammar)
) {
  Write-Host "whisper-rs checkout is incomplete, refreshing clone"
  Invoke-WhisperClone
}

$buildText = Get-Content $sysBuild -Raw
$buildText = $buildText.Replace(
  'if env::var("WHISPER_DONT_GENERATE_BINDINGS").is_ok() {',
  'if cfg!(target_os = "windows") || env::var("WHISPER_DONT_GENERATE_BINDINGS").is_ok() {'
)
$buildText = $buildText.Replace(
  'let mut bindings = bindgen::Builder::default().header("wrapper.h");',
  'let bindings = bindgen::Builder::default().header("wrapper.h");'
)
# Patch build.rs: add -U__ARM_FEATURE_MATMUL_INT8 cflag for macOS ARM.
#
# Root cause: Apple Clang defines __ARM_FEATURE_MATMUL_INT8 based on the
# native CPU's i8mm capability even when -mcpu=...+noi8mm disables i8mm code
# generation.  ggml-cpu-quants.c uses always_inline vmmlaq_s32 (which requires
# the i8mm target feature) inside a block guarded only by
# #ifdef __ARM_FEATURE_MATMUL_INT8.  When that macro is defined but the
# enclosing function is compiled without i8mm support the compiler emits a
# fatal "always_inline function requires target feature 'i8mm'" error.
#
# Undefining the macro via cflag/cxxflag forces ggml to take the non-i8mm
# fallback path.  Using config.cflag() / config.cxxflag() (rather than
# config.define("CMAKE_C_FLAGS", ...)) is essential: the cmake Rust crate
# builds its own CMAKE_C_FLAGS from the cc crate and appends it to the cmake
# command AFTER any user-supplied .define() calls, overriding them.  The
# cflag/cxxflag values, by contrast, are appended to the crate's own flags.
$buildText = $buildText.Replace(
  '    let destination = config.build();',
  '    if target.contains("apple") { config.cflag("-U__ARM_FEATURE_MATMUL_INT8"); config.cxxflag("-U__ARM_FEATURE_MATMUL_INT8"); }' + "`n" + '    let destination = config.build();'
)
Set-Content -Path $sysBuild -Value $buildText -NoNewline

$bindingsText = Get-Content $sysBindings -Raw
$bindingsText = [regex]::Replace(
  $bindingsText,
  '(?s)const _: \(\) = \{.*?^};\r?\n',
  '',
  [System.Text.RegularExpressions.RegexOptions]::Multiline
)
$bindingsText = $bindingsText.Replace(
  'unsafe { ::std::mem::transmute(self._bitfield_1.get(0usize, 24u8) as u32) }',
  'self._bitfield_1.get(0usize, 24u8) as u32 as ::std::os::raw::c_int'
)
$bindingsText = $bindingsText.Replace(
  "unsafe {\r`n            let val: u32 = ::std::mem::transmute(val);\r`n            self._bitfield_1.set(0usize, 24u8, val as u64)\r`n        }",
  "let val = val as u32;\r`n        self._bitfield_1.set(0usize, 24u8, val as u64)"
)
$bindingsText = $bindingsText.Replace(
  "unsafe {\r`n            ::std::mem::transmute(<__BindgenBitfieldUnit<[u8; 3usize]>>::raw_get(\r`n                ::std::ptr::addr_of!((*this)._bitfield_1),\r`n                0usize,\r`n                24u8,\r`n            ) as u32)\r`n        }",
  "<__BindgenBitfieldUnit<[u8; 3usize]>>::raw_get(\r`n            ::std::ptr::addr_of!((*this)._bitfield_1),\r`n            0usize,\r`n            24u8,\r`n        ) as u32 as ::std::os::raw::c_int"
)
$bindingsText = $bindingsText.Replace(
  "unsafe {\r`n            let val: u32 = ::std::mem::transmute(val);\r`n            <__BindgenBitfieldUnit<[u8; 3usize]>>::raw_set(\r`n                ::std::ptr::addr_of_mut!((*this)._bitfield_1),\r`n                0usize,\r`n                24u8,\r`n                val as u64,\r`n            )\r`n        }",
  "let val = val as u32;\r`n        <__BindgenBitfieldUnit<[u8; 3usize]>>::raw_set(\r`n            ::std::ptr::addr_of_mut!((*this)._bitfield_1),\r`n            0usize,\r`n            24u8,\r`n            val as u64,\r`n        )"
)
$bindingsText = $bindingsText.Replace(
  'let _flags2: u32 = unsafe { ::std::mem::transmute(_flags2) };',
  'let _flags2 = _flags2 as u32;'
)
$bindingsText = [regex]::Replace(
  $bindingsText,
  '(?s)pub fn set__flags2\(&mut self, val: ::std::os::raw::c_int\) \{\s*unsafe \{\s*let val: u32 = ::std::mem::transmute\(val\);\s*self\._bitfield_1\.set\(0usize, 24u8, val as u64\)\s*\}\s*\}',
  "pub fn set__flags2(&mut self, val: ::std::os::raw::c_int) {`r`n        let val = val as u32;`r`n        self._bitfield_1.set(0usize, 24u8, val as u64)`r`n    }"
)
$bindingsText = [regex]::Replace(
  $bindingsText,
  '(?s)pub unsafe fn _flags2_raw\(this: \*const Self\) -> ::std::os::raw::c_int \{\s*unsafe \{\s*::std::mem::transmute\(<__BindgenBitfieldUnit<\[u8; 3usize\]>>::raw_get\(\s*::std::ptr::addr_of!\(\(\*this\)\._bitfield_1\),\s*0usize,\s*24u8,\s*\) as u32\)\s*\}\s*\}',
  "pub unsafe fn _flags2_raw(this: *const Self) -> ::std::os::raw::c_int {`r`n        <__BindgenBitfieldUnit<[u8; 3usize]>>::raw_get(`r`n            ::std::ptr::addr_of!((*this)._bitfield_1),`r`n            0usize,`r`n            24u8,`r`n        ) as u32 as ::std::os::raw::c_int`r`n    }"
)
$bindingsText = [regex]::Replace(
  $bindingsText,
  '(?s)pub unsafe fn set__flags2_raw\(this: \*mut Self, val: ::std::os::raw::c_int\) \{\s*unsafe \{\s*let val: u32 = ::std::mem::transmute\(val\);\s*<__BindgenBitfieldUnit<\[u8; 3usize\]>>::raw_set\(\s*::std::ptr::addr_of_mut!\(\(\*this\)\._bitfield_1\),\s*0usize,\s*24u8,\s*val as u64,\s*\)\s*\}\s*\}',
  "pub unsafe fn set__flags2_raw(this: *mut Self, val: ::std::os::raw::c_int) {`r`n        let val = val as u32;`r`n        <__BindgenBitfieldUnit<[u8; 3usize]>>::raw_set(`r`n            ::std::ptr::addr_of_mut!((*this)._bitfield_1),`r`n            0usize,`r`n            24u8,`r`n            val as u64,`r`n        )`r`n    }"
)
Set-Content -Path $sysBindings -Value $bindingsText -NoNewline

$commonLoggingText = Get-Content $commonLogging -Raw
$commonLoggingText = $commonLoggingText.Replace("repr(i32)", "repr(u32)")
Set-Content -Path $commonLogging -Value $commonLoggingText -NoNewline

$grammarText = Get-Content $grammar -Raw
$grammarText = $grammarText.Replace("repr(i32)", "repr(u32)")
Set-Content -Path $grammar -Value $grammarText -NoNewline

Set-Content -Path $cacheStamp -Value $repoCommit -NoNewline
