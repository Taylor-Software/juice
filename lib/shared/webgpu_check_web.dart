import 'dart:js_interop';

@JS('navigator.gpu')
external JSAny? get _navigatorGpu;

/// True when the browser exposes WebGPU (required by MediaPipe GenAI).
bool get hasWebGpu => _navigatorGpu != null;
