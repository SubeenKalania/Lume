#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"
// Register plugins for newly created sub-windows.
#include <desktop_multi_window/desktop_multi_window_plugin.h>
#include <bitsdojo_window_windows/bitsdojo_window_plugin.h>
#include <window_manager/window_manager_plugin.h>
#include <screen_retriever/screen_retriever_plugin.h>
#include <file_selector_windows/file_selector_windows.h>
#include <url_launcher_windows/url_launcher_windows.h>

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  // Ensure plugins are registered for any additional engines created by
  // desktop_multi_window (child windows). This mirrors the main engine's
  // registrations so plugins like window_manager and bitsdojo_window work
  // in sub-windows as well.
  DesktopMultiWindowSetWindowCreatedCallback([](void* controller) {
    auto* flutter_view_controller =
        reinterpret_cast<flutter::FlutterViewController*>(controller);
    auto* registry = flutter_view_controller->engine();
    // Register required plugins for child engines (exclude DesktopMultiWindow).
    BitsdojoWindowPluginRegisterWithRegistrar(
        registry->GetRegistrarForPlugin("BitsdojoWindowPlugin"));
    WindowManagerPluginRegisterWithRegistrar(
        registry->GetRegistrarForPlugin("WindowManagerPlugin"));
    ScreenRetrieverPluginRegisterWithRegistrar(
        registry->GetRegistrarForPlugin("ScreenRetrieverPlugin"));
    FileSelectorWindowsRegisterWithRegistrar(
        registry->GetRegistrarForPlugin("FileSelectorWindows"));
    UrlLauncherWindowsRegisterWithRegistrar(
        registry->GetRegistrarForPlugin("UrlLauncherWindows"));
  });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
