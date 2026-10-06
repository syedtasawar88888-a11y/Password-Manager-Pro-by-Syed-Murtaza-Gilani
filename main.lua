Require "import"
import "android.widget.*"
import "android.view.*"
import "android.app.*"
import "android.graphics.*"
import "android.view.animation.*"
import "android.speech.tts.TextToSpeech"
import "java.util.Locale"
import "android.os.Handler"
import "android.os.Looper"
import "android.content.ClipboardManager"
import "android.content.ClipData"
import "android.content.Context"
import "android.content.SharedPreferences"
import "android.content.Intent"
import "android.net.Uri"
import "android.content.DialogInterface"
import "android.view.inputmethod.InputMethodManager"
import "java.io.File"
import "com.androlua.Http"
import "cjson"
import "com.androlua.LuaDialog"

-- Safe Context Initialization
local ctx = service or activity
if not ctx then
    pcall(function()
        local ActivityThread = luajava.bindClass("android.app.ActivityThread")
        local currentActivity = ActivityThread.currentActivityThread().getApplication()
        if currentActivity then ctx = currentActivity end
    end)
end

-- Version Variable (the updater reads this exact line from GitHub, do not change its format)
local CURRENT_VERSION = "1.3"

-- Update Source (GitHub raw link of main.lua)
local UPDATE_URL = "https://raw.githubusercontent.com/syedtasawar88888-a11y/Password-Manager-Pro-by-Syed-Murtaza-Gilani/refs/heads/main/main.lua"
local REPO_URL = "https://github.com/syedtasawar88888-a11y/Password-Manager-Pro-by-Syed-Murtaza-Gilani"

-- Remember the script file path so the update can replace it
local SCRIPT_PATH = nil
pcall(function()
  local src = debug.getinfo(1, "S").source
  if src and src:sub(1, 1) == "@" then
    SCRIPT_PATH = src:sub(2)
  end
end)

-- Shared Preferences for Settings
local sp = ctx.getSharedPreferences("PasswordManagerProPrefs", Context.MODE_PRIVATE)

local function saveData(key, val)
  local editor = sp.edit()
  editor.putString(key, val)
  editor.commit()
end

local function getData(key, defaultVal)
  return sp.getString(key, defaultVal or "")
end

-- TTS Toggle (Default: true)
local ttsEnabled = getData("ttsEnabled", "true") == "true"
local appPin = getData("appPin", "")
local isPasswordTypePin = getData("isPasswordTypePin", "false") == "true"

-- Forward Declaration of tts
local tts

local function speakText(msg)
  if ttsEnabled then 
    if tts then 
      pcall(function()
        tts.speak(msg, TextToSpeech.QUEUE_FLUSH, nil) 
      end)
    end
  end
end

-- TTS Engine Initialization with Language Set
tts = TextToSpeech(ctx, TextToSpeech.OnInitListener{
  onInit = function(status)
    if status == TextToSpeech.SUCCESS then
      pcall(function()
        tts.setLanguage(Locale.ENGLISH)
      end)
      speakText("Welcome to Password Manager Pro by Syed Murtaza Gilani")
    end
  end
})

-- Utility to hide soft keyboard
local function hideKeyboard(view)
  if view then
    local imm = ctx.getSystemService(Context.INPUT_METHOD_SERVICE)
    imm.hideSoftInputFromWindow(view.getWindowToken(), 0)
  end
end

-- Forward Declarations
local dlgMain, dlgAddEdit, dlgDetail, dlgGenerator, dlgHub, dlgAboutApp, dlgDev, dlgContact, dlgOptions, dlgExit, dlgSearch, dlgStoredList, dlgPin, dlgPinSetup, dlgLockChoice, dlgUpdate

function dismissAllDialogs()
  if dlgMain then pcall(function() dlgMain.dismiss() dlgMain = nil end) end
  if dlgAddEdit then pcall(function() dlgAddEdit.dismiss() dlgAddEdit = nil end) end
  if dlgDetail then pcall(function() dlgDetail.dismiss() dlgDetail = nil end) end
  if dlgGenerator then pcall(function() dlgGenerator.dismiss() dlgGenerator = nil end) end
  if dlgHub then pcall(function() dlgHub.dismiss() dlgHub = nil end) end
  if dlgAboutApp then pcall(function() dlgAboutApp.dismiss() dlgAboutApp = nil end) end
  if dlgDev then pcall(function() dlgDev.dismiss() dlgDev = nil end) end
  if dlgContact then pcall(function() dlgContact.dismiss() dlgContact = nil end) end
  if dlgOptions then pcall(function() dlgOptions.dismiss() dlgOptions = nil end) end
  if dlgExit then pcall(function() dlgExit.dismiss() dlgExit = nil end) end
  if dlgSearch then pcall(function() dlgSearch.dismiss() dlgSearch = nil end) end
  if dlgStoredList then pcall(function() dlgStoredList.dismiss() dlgStoredList = nil end) end
  if dlgPin then pcall(function() dlgPin.dismiss() dlgPin = nil end) end
  if dlgPinSetup then pcall(function() dlgPinSetup.dismiss() dlgPinSetup = nil end) end
  if dlgLockChoice then pcall(function() dlgLockChoice.dismiss() dlgLockChoice = nil end) end
end

local function copyToClipboard(textToCopy, label)
  local clipboard = ctx.getSystemService(Context.CLIPBOARD_SERVICE)
  local clip = ClipData.newPlainText(label or "Copied Credential", textToCopy)
  clipboard.setPrimaryClip(clip)
  Toast.makeText(ctx, "Copied: " .. (label or "Text"), Toast.LENGTH_SHORT).show()
end

local function openUrl(url)
  if url and url ~= "" then
    dismissAllDialogs()
    local intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    ctx.startActivity(intent)
  else
    Toast.makeText(ctx, "Link will be updated soon!", Toast.LENGTH_SHORT).show()
  end
end

-- Data Store
local passwords = {}

local function serializeTable(val)
  if type(val) == "table" then
    local str = "{"
    for k, v in pairs(val) do
      local keyStr = type(k) == "number" and "["..k.."]" or '["'..tostring(k)..'"]'
      str = str .. keyStr .. "=" .. serializeTable(v) .. ","
    end
    return str .. "}"
  elseif type(val) == "string" then
    return '"' .. val:gsub('"', '\\"'):gsub('\n', '\\n') .. '"'
  else
    return tostring(val)
  end
end

local function deserializeTable(str)
  if str and str ~= "" then
    local func = loadstring("return " .. str)
    if func then
      local status, result = pcall(func)
      if status and type(result) == "table" then return result end
    end
  end
  return nil
end

local function saveAllDataToStorage()
  saveData("passwords", serializeTable(passwords))
  saveData("ttsEnabled", tostring(ttsEnabled))
  saveData("appPin", appPin)
  saveData("isPasswordTypePin", tostring(isPasswordTypePin))
end

local function loadAllDataFromStorage()
  local savedPass = deserializeTable(getData("passwords", ""))
  if savedPass then passwords = savedPass end
  appPin = getData("appPin", "")
  isPasswordTypePin = getData("isPasswordTypePin", "false") == "true"
end

loadAllDataFromStorage()

local showMainDialog, showAddEditPasswordDialog, showPasswordDetailDialog, showPasswordGeneratorDialog
local showAboutHubDialog, showAboutAppDialog, showAboutDeveloperDialog, showContactDialog
local showMoreOptionsDialog, showExitConfirmation, showSearchDialog, showStoredPasswordsListDialog, showPinVerificationDialog, showPinSetupDialog, showDisablePinDialog, showLockChoiceDialog
local showUpdateDialog, checkForUpdates

local function setupOverlayWindow(dialog)
  local window = dialog.getWindow()
  if service then
    window.setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
  end
  dialog.setCancelable(true)
  window.setFlags(WindowManager.LayoutParams.FLAG_ALT_FOCUSABLE_IM, WindowManager.LayoutParams.FLAG_ALT_FOCUSABLE_IM)
end

local function setupInputOverlayWindow(dialog)
  local window = dialog.getWindow()
  if service then
    window.setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
  end
  dialog.setCancelable(true)
  window.clearFlags(WindowManager.LayoutParams.FLAG_ALT_FOCUSABLE_IM)
  window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_STATE_VISIBLE)
end

local function exitApp()
  saveAllDataToStorage()
  speakText("Thank you for using this extension")
  if tts then
    Handler(Looper.getMainLooper()).postDelayed(Runnable{
      run = function()
        pcall(function() tts.stop() tts.shutdown() end)
      end
    }, 800)
  end
  if dlgUpdate then pcall(function() dlgUpdate.dismiss() dlgUpdate = nil end) end
  dismissAllDialogs()
end

-- ===================== AUTO UPDATE SYSTEM =====================

-- Compare two version strings like "1.2" and "1.10". Returns true if remote is newer than local.
local function isNewerVersion(remoteVer, localVer)
  local function split(v)
    local parts = {}
    for num in tostring(v):gmatch("%d+") do
      parts[#parts + 1] = tonumber(num)
    end
    return parts
  end
  local r = split(remoteVer)
  local l = split(localVer)
  local n = math.max(#r, #l)
  for i = 1, n do
    local rv = r[i] or 0
    local lv = l[i] or 0
    if rv > lv then return true end
    if rv < lv then return false end
  end
  return false
end

-- Run a function safely on the main thread
local function runOnMain(fn)
  Handler(Looper.getMainLooper()).post(Runnable{
    run = function()
      pcall(fn)
    end
  })
end

-- Try to replace the running extension file with the new code
local function installUpdate(newContent)
  if not newContent or #newContent < 1000 or not newContent:find("CURRENT_VERSION", 1, true) then
    return false, "Downloaded file looks invalid."
  end
  if not SCRIPT_PATH or SCRIPT_PATH == "" then
    return false, "Could not find the extension file path."
  end
  local f = File(SCRIPT_PATH)
  if not f.exists() then
    return false, "Extension file not found."
  end
  local ok, err = pcall(function()
    local fh = io.open(SCRIPT_PATH, "wb")
    if not fh then error("Cannot write to file") end
    fh:write(newContent)
    fh:close()
  end)
  if not ok then
    return false, tostring(err)
  end
  return true
end

showUpdateDialog = function(newVer, newContent)
  if dlgUpdate then pcall(function() dlgUpdate.dismiss() dlgUpdate = nil end) end

  local updLayout = {
    LinearLayout, orientation="vertical", padding="20dp", gravity="center",
    {TextView, text="Update Available", textSize="22sp", textColor=0xFF1565C0, paddingBottom="12dp"},
    {TextView, text="Hey! Your update has arrived. Please update the extension now.\n\nYour version: " .. CURRENT_VERSION .. "\nNew version: " .. tostring(newVer) .. "\n\nYour saved passwords will stay safe.", textSize="16sp", paddingBottom="14dp"},
    {
      Button, text="Update Now", paddingTop="8dp",
      onClick=function()
        local ok, err = installUpdate(newContent)
        if ok then
          speakText("Update installed successfully. Please close and run the extension again.")
          Toast.makeText(ctx, "Updated to version " .. tostring(newVer) .. ". Please run the extension again.", Toast.LENGTH_LONG).show()
          if dlgUpdate then pcall(function() dlgUpdate.dismiss() dlgUpdate = nil end) end
          saveAllDataToStorage()
          dismissAllDialogs()
        else
          speakText("Automatic update failed. Opening the download page.")
          Toast.makeText(ctx, "Auto update failed: " .. tostring(err), Toast.LENGTH_LONG).show()
          if dlgUpdate then pcall(function() dlgUpdate.dismiss() dlgUpdate = nil end) end
          openUrl(REPO_URL)
        end
      end
    },
    {
      Button, text="Open GitHub Page", paddingTop="6dp",
      onClick=function()
        if dlgUpdate then pcall(function() dlgUpdate.dismiss() dlgUpdate = nil end) end
        openUrl(REPO_URL)
      end
    },
    {
      Button, text="Later", paddingTop="6dp",
      onClick=function()
        if dlgUpdate then pcall(function() dlgUpdate.dismiss() dlgUpdate = nil end) end
        speakText("Update postponed")
      end
    }
  }

  dlgUpdate = Dialog(ctx)
  dlgUpdate.setContentView(loadlayout(updLayout))
  setupOverlayWindow(dlgUpdate)
  dlgUpdate.setOnCancelListener(DialogInterface.OnCancelListener{
    onCancel = function() dlgUpdate = nil end
  })
  dlgUpdate.show()
  speakText("Update available. Version " .. tostring(newVer) .. " is ready. Please update the extension.")
end

-- manual = true when the user taps "Check for Updates" (shows result even when up to date)
checkForUpdates = function(manual)
  if manual then
    speakText("Checking for updates")
    Toast.makeText(ctx, "Checking for updates...", Toast.LENGTH_SHORT).show()
  end
  local url = UPDATE_URL .. "?t=" .. tostring(os.time())
  local started = pcall(function()
    Http.get(url, function(code, content)
      runOnMain(function()
        if code == 200 and content and content ~= "" then
          local remoteVer = content:match('local%s+CURRENT_VERSION%s*=%s*"([%d%.]+)"')
          if remoteVer and isNewerVersion(remoteVer, CURRENT_VERSION) then
            showUpdateDialog(remoteVer, content)
          elseif manual then
            speakText("You are using the latest version")
            Toast.makeText(ctx, "You are using the latest version (" .. CURRENT_VERSION .. ")", Toast.LENGTH_SHORT).show()
          end
        elseif manual then
          speakText("Could not check for updates. Please check your internet connection.")
          Toast.makeText(ctx, "Could not check for updates. Check your internet.", Toast.LENGTH_LONG).show()
        end
      end)
    end)
  end)
  if not started and manual then
    Toast.makeText(ctx, "Update check failed to start.", Toast.LENGTH_SHORT).show()
  end
end

-- ===================== END AUTO UPDATE SYSTEM =====================

-- PIN / Password Setup Dialog
showPinSetupDialog = function(asPassword)
  dismissAllDialogs()
  local idsPin = {}
  local inputHint = asPassword and "Enter password (letters, symbols)..." or "Enter PIN digits..."
  local inputTypeVal = asPassword and 129 or 18
  
  local pinLayout = {
    LinearLayout, orientation="vertical", padding="20dp", gravity="center",
    {TextView, text=(asPassword and "Security Password Setup" or "Security PIN Setup"), textSize="20sp", paddingBottom="12dp"},
    {TextView, text=(asPassword and "Enter Custom Password (QWERTY Keyboard):" or "Enter Security PIN (Numbers Only):"), textSize="14sp", paddingBottom="8dp"},
    {EditText, id="edtPinInput", hint=inputHint, inputType=inputTypeVal, textSize="18sp", layout_width="fill", focusable=true, focusableInTouchMode=true},
    {
      Button, text="Done / Hide Keyboard", paddingTop="4dp",
      onClick=function() hideKeyboard(idsPin.edtPinInput) end
    },
    {
      Button, text="Save Lock", paddingTop="10dp",
      onClick=function()
        appPin = tostring(idsPin.edtPinInput.getText())
        if appPin == "" then
          Toast.makeText(ctx, "Lock cannot be blank!", Toast.LENGTH_SHORT).show()
          return
        end
        saveAllDataToStorage()
        speakText("Security lock saved successfully")
        Toast.makeText(ctx, "Security Lock updated!", Toast.LENGTH_SHORT).show()
        if dlgPinSetup then dlgPinSetup.dismiss() dlgPinSetup = nil end
        showMoreOptionsDialog()
      end
    },
    {
      Button, text="Back", paddingTop="6dp",
      onClick=function() 
        if dlgPinSetup then dlgPinSetup.dismiss() dlgPinSetup = nil end 
        showLockChoiceDialog() 
      end
    }
  }

  dlgPinSetup = Dialog(ctx)
  dlgPinSetup.setContentView(loadlayout(pinLayout, idsPin))
  setupInputOverlayWindow(dlgPinSetup)
  dlgPinSetup.setOnCancelListener(DialogInterface.OnCancelListener{
    onCancel = function() showMoreOptionsDialog() end
  })
  dlgPinSetup.show()
end

-- Lock Choice Dialog
showLockChoiceDialog = function()
  dismissAllDialogs()
  local choiceLayout = {
    LinearLayout, orientation="vertical", padding="20dp", gravity="center",
    {TextView, text="Choose Security Lock Type", textSize="20sp", paddingBottom="15sp"},
    {
      Button, text="Set Numeric PIN", paddingTop="8dp",
      onClick=function()
        if dlgLockChoice then dlgLockChoice.dismiss() dlgLockChoice = nil end
        showPinSetupDialog(false)
      end
    },
    {
      Button, text="Set Text Password (QWERTY / Symbols)", paddingTop="8dp",
      onClick=function()
        if dlgLockChoice then dlgLockChoice.dismiss() dlgLockChoice = nil end
        showPinSetupDialog(true)
      end
    },
    {
      Button, text="Back", paddingTop="12dp",
      onClick=function()
        if dlgLockChoice then dlgLockChoice.dismiss() dlgLockChoice = nil end
        showMoreOptionsDialog()
      end
    }
  }

  dlgLockChoice = Dialog(ctx)
  dlgLockChoice.setContentView(loadlayout(choiceLayout))
  setupOverlayWindow(dlgLockChoice)
  dlgLockChoice.setOnCancelListener(DialogInterface.OnCancelListener{
    onCancel = function() showMoreOptionsDialog() end
  })
  dlgLockChoice.show()
end

-- Turn Off PIN Dialog
showDisablePinDialog = function()
  dismissAllDialogs()
  local idsDisable = {}
  local inputTypeVal = isPasswordTypePin and 129 or 18
  local disableLayout = {
    LinearLayout, orientation="vertical", padding="20dp", gravity="center",
    {TextView, text="Turn Off Security Lock", textSize="20sp", paddingBottom="12dp"},
    {TextView, text="Enter your current PIN or password to turn off security lock:", textSize="14sp", paddingBottom="8dp"},
    {EditText, id="edtDisablePin", hint="Enter current lock...", inputType=inputTypeVal, textSize="18sp", layout_width="fill", focusable=true, focusableInTouchMode=true},
    {
      Button, text="Done / Hide Keyboard", paddingTop="4dp",
      onClick=function() hideKeyboard(idsDisable.edtDisablePin) end
    },
    {
      Button, text="Turn Off Lock", paddingTop="10dp",
      onClick=function()
        local entered = tostring(idsDisable.edtDisablePin.getText())
        if entered == appPin then
          appPin = ""
          isPasswordTypePin = false
          saveAllDataToStorage()
          speakText("Security lock turned off successfully")
          Toast.makeText(ctx, "Security Lock disabled!", Toast.LENGTH_SHORT).show()
          if dlgPinSetup then dlgPinSetup.dismiss() dlgPinSetup = nil end
          showMoreOptionsDialog()
        else
          speakText("Incorrect code")
          Toast.makeText(ctx, "Incorrect code, try again!", Toast.LENGTH_SHORT).show()
        end
      end
    },
    {
      Button, text="Back", paddingTop="6dp",
      onClick=function() 
        if dlgPinSetup then dlgPinSetup.dismiss() dlgPinSetup = nil end 
        showMoreOptionsDialog() 
      end
    }
  }

  dlgPinSetup = Dialog(ctx)
  dlgPinSetup.setContentView(loadlayout(disableLayout, idsDisable))
  setupInputOverlayWindow(dlgPinSetup)
  dlgPinSetup.setOnCancelListener(DialogInterface.OnCancelListener{
    onCancel = function() showMoreOptionsDialog() end
  })
  dlgPinSetup.show()
end

-- PIN Verification Dialog on Startup
showPinVerificationDialog = function(onSuccess)
  dismissAllDialogs()
  local idsVerify = {}
  local inputTypeVal = isPasswordTypePin and 129 or 18
  local verifyLayout = {
    LinearLayout, orientation="vertical", padding="20dp", gravity="center",
    {TextView, text="Authentication required", textSize="22sp", textColor=0xFF1565C0, paddingBottom="12dp"},
    {TextView, text="Enter your security PIN or password to open Password Manager Pro:", textSize="15sp", paddingBottom="12dp"},
    {EditText, id="edtVerifyPin", hint="Enter lock...", inputType=inputTypeVal, textSize="20sp", layout_width="fill", focusable=true, focusableInTouchMode=true},
    {
      Button, text="Done / Hide Keyboard", paddingTop="4dp",
      onClick=function() hideKeyboard(idsVerify.edtVerifyPin) end
    },
    {
      Button, text="Unlock", paddingTop="12dp",
      onClick=function()
        local entered = tostring(idsVerify.edtVerifyPin.getText())
        if entered == appPin then
          speakText("Unlocked successfully")
          if dlgPin then dlgPin.dismiss() dlgPin = nil end
          onSuccess()
        else
          speakText("Incorrect code")
          Toast.makeText(ctx, "Incorrect code, try again!", Toast.LENGTH_SHORT).show()
        end
      end
    },
    {
      Button, text="Exit", paddingTop="6dp",
      onClick=function() exitApp() end
    }
  }

  dlgPin = Dialog(ctx)
  dlgPin.setContentView(loadlayout(verifyLayout, idsVerify))
  setupInputOverlayWindow(dlgPin)
  dlgPin.setCancelable(false)
  dlgPin.show()
end

-- Password Generator Dialog
showPasswordGeneratorDialog = function(callback)
  local idsGen = {}
  local genLayout = {
    LinearLayout, orientation="vertical", padding="16dp", gravity="center",
    {TextView, text="Secure Password Generator", textSize="20sp", paddingBottom="12dp"},
    {
      EditText, id="edtGeneratedPass", hint="Generated password will appear here...", inputType="textVisiblePassword", textSize="16sp", layout_width="fill", focusable=true, focusableInTouchMode=true
    },
    {
      Button, text="Done / Hide Keyboard",
      onClick=function() hideKeyboard(idsGen.edtGeneratedPass) end
    },
    {
      LinearLayout, orientation="horizontal", layout_width="fill", paddingTop="10dp", gravity="center",
      {
        Button, text="Generate",
        onClick=function()
          local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789@#$%&*!"
          local length = 12
          local res = ""
          math.randomseed(os.time())
          for i = 1, length do
            local randIdx = math.random(1, #chars)
            res = res .. chars:sub(randIdx, randIdx)
          end
          idsGen.edtGeneratedPass.setText(res)
          speakText("Password generated")
        end
      },
      {
        Button, text="Use Password",
        onClick=function()
          local p = tostring(idsGen.edtGeneratedPass.getText())
          if p ~= "" then
            if dlgGenerator then dlgGenerator.dismiss() dlgGenerator = nil end
            if callback then callback(p) end
          else
            Toast.makeText(ctx, "Generate a password first!", Toast.LENGTH_SHORT).show()
          end
        end
      }
    },
    {
      Button, text="Back", paddingTop="10dp",
      onClick=function() 
        if dlgGenerator then dlgGenerator.dismiss() dlgGenerator = nil end 
      end
    }
  }

  dlgGenerator = Dialog(ctx)
  dlgGenerator.setContentView(loadlayout(genLayout, idsGen))
  setupInputOverlayWindow(dlgGenerator)
  dlgGenerator.setOnCancelListener(DialogInterface.OnCancelListener{
    onCancel = function() dlgGenerator = nil end
  })
  dlgGenerator.show()
end

-- Credential Detail Dialog
showPasswordDetailDialog = function(item, index)
  local isPasswordRevealed = false
  local idsDetail = {}
  
  local detailLayout = {
    LinearLayout, orientation="vertical", padding="16dp",
    {TextView, text="Credential Details", textSize="22sp", gravity="center", paddingBottom="12dp"},
    {TextView, text="Title: " .. tostring(item.title), textSize="18sp", textColor=0xFF1565C0, paddingBottom="6dp"},
    {TextView, text="Category: " .. tostring(item.category or "General"), textSize="15sp", paddingBottom="6dp"},
    {TextView, text="Username / Email: " .. tostring(item.username), textSize="16sp", paddingBottom="6dp"},
    {TextView, id="txtPasswordDisplay", text="Password: ********", textSize="16sp", textColor=0xFF2E7D32, paddingBottom="6dp"},
    {TextView, text="Notes: " .. tostring(item.notes or "None"), textSize="14sp", paddingBottom="12dp"},
    {
      Button, text="Reveal Password",
      onClick=function()
        isPasswordRevealed = not isPasswordRevealed
        if isPasswordRevealed then
          idsDetail.txtPasswordDisplay.setText("Password: " .. tostring(item.password))
          speakText("Password revealed: " .. tostring(item.password))
        else
          idsDetail.txtPasswordDisplay.setText("Password: ********")
          speakText("Password hidden")
        end
      end
    },
    {
      Button, text="Copy Username / Email",
      onClick=function() copyToClipboard(item.username, "Username") end
    },
    {
      Button, text="Copy Password",
      onClick=function() copyToClipboard(item.password, "Password") end
    },
    {
      Button, text="Edit Credential",
      onClick=function() if dlgDetail then dlgDetail.dismiss() dlgDetail = nil end showAddEditPasswordDialog(item, index) end
    },
    {
      Button, text="Delete Credential",
      onClick=function()
        table.remove(passwords, index)
        saveAllDataToStorage()
        speakText("Credential deleted")
        Toast.makeText(ctx, "Credential deleted!", Toast.LENGTH_SHORT).show()
        if dlgDetail then dlgDetail.dismiss() dlgDetail = nil end
        showStoredPasswordsListDialog()
      end
    },
    {
      Button, text="Back",
      onClick=function() if dlgDetail then dlgDetail.dismiss() dlgDetail = nil end showStoredPasswordsListDialog() end
    }
  }

  dlgDetail = Dialog(ctx)
  dlgDetail.setContentView(loadlayout(detailLayout, idsDetail))
  setupOverlayWindow(dlgDetail)
  dlgDetail.setOnCancelListener(DialogInterface.OnCancelListener{
    onCancel = function() showStoredPasswordsListDialog() end
  })
  dlgDetail.show()
end

-- Stored Passwords List Dialog
showStoredPasswordsListDialog = function()
  dismissAllDialogs()
  local idsList = {}
  local listLayout = {
    LinearLayout, orientation="vertical", padding="16dp",
    {TextView, text="Stored Credentials List", textSize="22sp", gravity="center", paddingBottom="12dp"},
    {
      ScrollView, layout_height="240dp", layout_width="fill",
      { LinearLayout, id="storedContainer", orientation="vertical" }
    },
    {
      Button, text="Back to Home", paddingTop="10dp",
      onClick=function() showMainDialog() end
    }
  }

  local contentView = loadlayout(listLayout, idsList)

  if #passwords == 0 then
    local emptyTxt = TextView(ctx)
    emptyTxt.setText("No passwords saved yet!")
    emptyTxt.setTextSize(16)
    idsList.storedContainer.addView(emptyTxt)
  else
    for i, item in ipairs(passwords) do
      local btn = Button(ctx)
      btn.setText(item.title .. " [" .. (item.category or "General") .. "]")
      btn.setTextSize(15)
      local currentIdx = i
      btn.setOnClickListener(View.OnClickListener{
        onClick = function()
          if dlgStoredList then dlgStoredList.dismiss() dlgStoredList = nil end
          showPasswordDetailDialog(item, currentIdx)
        end
      })
      idsList.storedContainer.addView(btn)
    end
  end

  dlgStoredList = Dialog(ctx)
  dlgStoredList.setContentView(contentView)
  setupOverlayWindow(dlgStoredList)
  dlgStoredList.setOnCancelListener(DialogInterface.OnCancelListener{
    onCancel = function() showMainDialog() end
  })
  dlgStoredList.show()
end

-- Add / Edit Credential Dialog
showAddEditPasswordDialog = function(editItem, editIndex)
  dismissAllDialogs()
  local idsAE = {}
  local isEditing = (editItem ~= nil)
  local isPassVisible = false
  
  local aeLayout = {
    ScrollView, layout_width="fill", layout_height="wrap",
    {
      LinearLayout, orientation="vertical", padding="16dp",
      {TextView, text=(isEditing and "Edit Credential" or "Add New Credential"), textSize="22sp", gravity="center", paddingBottom="12dp"},
      {TextView, text="Account Title (e.g., Gmail, Facebook)", textSize="14sp"},
      {EditText, id="edtTitle", hint="Enter title...", text=(isEditing and editItem.title or ""), textSize="16sp", layout_width="fill", focusable=true, focusableInTouchMode=true},
      
      {TextView, text="Select Category", textSize="14sp", paddingTop="6dp"},
      {
        Spinner, id="spinnerCategory", layout_width="fill", layout_height="48dp"
      },
      {TextView, text="Or Type Custom Category (Optional)", textSize="12sp", paddingTop="4dp", textColor=0xFF757575},
      {EditText, id="edtCategoryCustom", hint="Leave blank to use selected category above", text="", textSize="15sp", layout_width="fill", focusable=true, focusableInTouchMode=true},
      
      {TextView, text="Username / Email", textSize="14sp", paddingTop="6dp"},
      {EditText, id="edtUsername", hint="Enter username or email...", text=(isEditing and editItem.username or ""), textSize="16sp", layout_width="fill", focusable=true, focusableInTouchMode=true},
      
      {TextView, text="Password (Supports Letters, Numbers & Symbols)", textSize="14sp", paddingTop="6dp"},
      {
        LinearLayout, orientation="horizontal", layout_width="fill",
        {EditText, id="edtPassword", hint="Enter password...", text=(isEditing and editItem.password or ""), inputType="textVisiblePassword", textSize="16sp", layout_weight=1, focusable=true, focusableInTouchMode=true},
        {
          Button, text="Generate",
          onClick=function()
            showPasswordGeneratorDialog(function(generated)
              idsAE.edtPassword.setText(generated)
            end)
          end
        }
      },
      {
        Button, id="btnTogglePass", text="Hide Password",
        onClick=function()
          isPassVisible = not isPassVisible
          if isPassVisible then
            idsAE.edtPassword.setInputType(129)
            idsAE.btnTogglePass.setText("Show Password")
            speakText("Password hidden")
          else
            idsAE.edtPassword.setInputType(144)
            idsAE.btnTogglePass.setText("Hide Password")
            speakText("Password shown")
          end
          idsAE.edtPassword.setSelection(string.len(tostring(idsAE.edtPassword.getText())))
        end
      },
      
      {TextView, text="Notes / Additional Info", textSize="14sp", paddingTop="6dp"},
      {EditText, id="edtNotes", hint="Optional notes...", text=(isEditing and editItem.notes or ""), textSize="16sp", lines=2, layout_width="fill", focusable=true, focusableInTouchMode=true},
      
      {
        Button, text="Done / Hide Keyboard", paddingTop="6dp",
        onClick=function()
          hideKeyboard(idsAE.edtNotes)
          hideKeyboard(idsAE.edtPassword)
          hideKeyboard(idsAE.edtUsername)
          hideKeyboard(idsAE.edtTitle)
          speakText("Keyboard hidden")
        end
      },
      
      {
        Button, text=(isEditing and "Update Credential" or "Save Credential"), paddingTop="10dp",
        onClick=function()
          local title = tostring(idsAE.edtTitle.getText())
          
          local category = tostring(idsAE.edtCategoryCustom.getText())
          if category == "" then
            pcall(function()
              category = tostring(idsAE.spinnerCategory.getSelectedItem())
            end)
          end
          if category == "" or category == "nil" then category = "General" end

          local username = tostring(idsAE.edtUsername.getText())
          local password = tostring(idsAE.edtPassword.getText())
          local notes = tostring(idsAE.edtNotes.getText())

          if title == "" or username == "" or password == "" then
            Toast.makeText(ctx, "Title, Username, and Password are required!", Toast.LENGTH_SHORT).show()
            return
          end

          local record = {
            title = title,
            category = category,
            username = username,
            password = password,
            notes = notes,
            date = os.date("%Y-%m-%d %H:%M")
          }

          if isEditing then
            passwords[editIndex] = record
            speakText("Credential updated successfully")
            Toast.makeText(ctx, "Credential Updated!", Toast.LENGTH_SHORT).show()
          else
            table.insert(passwords, 1, record)
            speakText("Password saved successfully")
            Toast.makeText(ctx, "Credential Saved!", Toast.LENGTH_SHORT).show()
          end

          saveAllDataToStorage()
          if dlgAddEdit then dlgAddEdit.dismiss() dlgAddEdit = nil end
          showMainDialog()
        end
      },
      {
        Button, text="Back", paddingTop="6dp",
        onClick=function() 
          if dlgAddEdit then dlgAddEdit.dismiss() dlgAddEdit = nil end 
          showMainDialog() 
        end
      }
    }
  }

  dlgAddEdit = Dialog(ctx)
  dlgAddEdit.setContentView(loadlayout(aeLayout, idsAE))
  
  pcall(function()
    local categories = {"General", "Gmail / Google", "Social Media", "Finance / Banking", "Entertainment", "Work / Professional"}
    local adapter = ArrayAdapter(ctx, android.R.layout.simple_spinner_item, categories)
    adapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
    idsAE.spinnerCategory.setAdapter(adapter)
    
    if isEditing and editItem.category then
      for i=1, #categories do
        if categories[i] == editItem.category then
          idsAE.spinnerCategory.setSelection(i - 1)
          break
        end
      end
    end
  end)

  setupInputOverlayWindow(dlgAddEdit)
  dlgAddEdit.setOnCancelListener(DialogInterface.OnCancelListener{
    onCancel = function() showMainDialog() end
  })
  dlgAddEdit.show()
end

-- Search Dialog
showSearchDialog = function()
  dismissAllDialogs()
  local idsSearch = {}
  local searchLayout = {
    LinearLayout, orientation="vertical", padding="16dp",
    {TextView, text="Search Credentials", textSize="22sp", gravity="center", paddingBottom="12dp"},
    {
      EditText, id="edtQuery", hint="Type title or username to search...", textSize="16sp", layout_width="fill", focusable=true, focusableInTouchMode=true
    },
    {
      Button, text="Done / Hide Keyboard",
      onClick=function() hideKeyboard(idsSearch.edtQuery) end
    },
    {
      Button, text="Search",
      onClick=function()
        local q = tostring(idsSearch.edtQuery.getText()):lower()
        if q == "" then
          Toast.makeText(ctx, "Enter a search query!", Toast.LENGTH_SHORT).show()
          return
        end
        idsSearch.resultsContainer.removeAllViews()
        local foundCount = 0
        for i, item in ipairs(passwords) do
          if item.title:lower():find(q) or item.username:lower():find(q) or item.category:lower():find(q) then
            foundCount = foundCount + 1
            local btn = Button(ctx)
            btn.setText(item.title .. " (" .. item.username .. ")")
            btn.setTextSize(15)
            local currentIdx = i
            btn.setOnClickListener(View.OnClickListener{
              onClick = function()
                if dlgSearch then dlgSearch.dismiss() dlgSearch = nil end
                showPasswordDetailDialog(item, currentIdx)
              end
            })
            idsSearch.resultsContainer.addView(btn)
          end
        end
        speakText("Found " .. foundCount .. " results")
        Toast.makeText(ctx, "Found " .. foundCount .. " results", Toast.LENGTH_SHORT).show()
      end
    },
    {
      ScrollView, layout_height="160dp", layout_width="fill", paddingTop="8dp",
      { LinearLayout, id="resultsContainer", orientation="vertical" }
    },
    {
      Button, text="Back", onClick=function() if dlgSearch then dlgSearch.dismiss() dlgSearch = nil end showMainDialog() end
    }
  }

  dlgSearch = Dialog(ctx)
  dlgSearch.setContentView(loadlayout(searchLayout, idsSearch))
  setupInputOverlayWindow(dlgSearch)
  dlgSearch.setOnCancelListener(DialogInterface.OnCancelListener{
    onCancel = function() showMainDialog() end
  })
  dlgSearch.show()
end

-- More Options Dialog
showMoreOptionsDialog = function()
  dismissAllDialogs()
  local optionsLayout = {
    LinearLayout, orientation="vertical", padding="16dp",
    {TextView, text="Settings & Options", textSize="22sp", gravity="center", padding