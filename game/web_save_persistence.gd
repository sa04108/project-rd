extends RefCounted

# 한 실행 문맥의 IDBFS 확정 상태만 관측한다. 탭 간 동시 쓰기나 강제 종료를 보장하지 않는다.
# 저장소 인스턴스가 바뀌어도 이 정적 인터페이스와 JS 관측기는 한 번만 설치한다.
const INTERFACE_NAME := "__rdWebSavePersistence"
const INSTALL_OBSERVER := """
(() => {
    const key = '__rdWebSavePersistence';
    const version = 1;
    try {
        const fs = typeof FS === 'object' && FS !== null ? FS : null;
        const module = typeof Module === 'object' && Module !== null ? Module : null;
        const existing = globalThis[key];
        if (existing) {
            return existing.version === version && existing.matches(fs) && !existing.disposed
                ? '' : 'observer_conflict';
        }
        let requested = 0;
        let committed = 0;
        let inFlight = 0;
        let error = '';
        let failedGeneration = -1;
        let retryAt = 0;
        let available = !!fs && typeof fs.syncfs === 'function';
        const canWarn = typeof globalThis.addEventListener === 'function' && typeof globalThis.removeEventListener === 'function';
        let disposed = false;
        let warningInstalled = false;
        const originalSync = available ? fs.syncfs : null;
        let wrappedSync = null;
        const originalExit = module && typeof module.onExit === 'function' ? module.onExit : null;
        let wrappedExit = null;
        const api = {
            version, state: 'durable', generation: 0, committed_generation: 0,
            error: '', available, disposed: false,
            matches(candidate) { return candidate === fs && (!available || fs.syncfs === wrappedSync); },
            markDirty() {
                if (disposed) return requested;
                requested += 1;
                publish();
                return requested;
            },
            takeRetry() {
                if (disposed || !available || !error || inFlight || performance.now() < retryAt) return false;
                retryAt = performance.now() + 2000;
                return true;
            },
            setUnavailable(reason) {
                if (disposed) return;
                available = false;
                error = reason;
                publish();
            },
            shutdown() {
                if (disposed) return;
                disposed = true;
                api.disposed = true;
                if (warningInstalled && canWarn) globalThis.removeEventListener('beforeunload', beforeUnload);
                warningInstalled = false;
                if (fs && fs.syncfs === wrappedSync) fs.syncfs = originalSync;
                if (module && module.onExit === wrappedExit) module.onExit = originalExit;
                if (globalThis[key] === api) delete globalThis[key];
            }
        };
        function beforeUnload(event) {
            if (!disposed && api.state !== 'durable') {
                event.preventDefault();
                event.returnValue = '';
            }
        }
        function publish() {
            if (disposed) return;
            api.generation = requested;
            api.committed_generation = committed;
            api.error = error;
            api.available = available;
            api.state = error || !available ? 'error' : (requested > committed ? 'pending' : 'durable');
            const needsWarning = api.state !== 'durable';
            if (canWarn && needsWarning && !warningInstalled) {
                globalThis.addEventListener('beforeunload', beforeUnload);
                warningInstalled = true;
            } else if (canWarn && !needsWarning && warningInstalled) {
                globalThis.removeEventListener('beforeunload', beforeUnload);
                warningInstalled = false;
            }
        }
        function finish(generation, failure) {
            if (disposed) return;
            inFlight = Math.max(0, inFlight - 1);
            if (failure != null) {
                error = 'sync_failed';
                failedGeneration = Math.max(failedGeneration, generation);
                retryAt = performance.now() + 2000;
            } else {
                committed = Math.max(committed, generation);
                if (available && generation >= failedGeneration) error = '';
            }
            publish();
        }
        if (available) {
            wrappedSync = function () {
                const args = Array.from(arguments);
                const callbackIndex = typeof args[0] === 'function' ? 0 : 1;
                const callback = args[callbackIndex];
                const populate = callbackIndex === 0 ? false : !!args[0];
                if (disposed || populate || typeof callback !== 'function') return originalSync.apply(this, args);
                const generation = requested;
                inFlight += 1;
                let completed = false;
                args[callbackIndex] = function () {
                    if (completed) return;
                    completed = true;
                    // 관측기 오류가 엔진의 완료 콜백 전달을 가로막지 않게 한다.
                    try { finish(generation, arguments[0]); }
                    finally { return callback.apply(this, arguments); }
                };
                try { return originalSync.apply(this, args); }
                catch (failure) {
                    // 완료 전 예외도 오류 콜백으로 전달해 엔진의 syncing 플래그를 해제한다.
                    if (!completed) return args[callbackIndex].call(this, failure || 'sync_threw');
                    throw failure;
                }
            };
            fs.syncfs = wrappedSync;
            if (fs.syncfs !== wrappedSync) {
                available = false;
                error = 'observer_unavailable';
            }
        } else {
            error = 'observer_unavailable';
        }
        // Godot 4.7.2의 onExit는 최종 FS sync 이후에 호출된다. atexit는 그보다 이르다.
        if (originalExit) {
            wrappedExit = function () {
                try { api.shutdown(); }
                finally { return originalExit.apply(this, arguments); }
            };
            module.onExit = wrappedExit;
        }
        globalThis[key] = api;
        if (globalThis[key] !== api) {
            api.shutdown();
            return 'observer_conflict';
        }
        publish();
        return '';
    } catch (_) {
        return 'observer_unavailable';
    }
})()
"""

static var _initialized := false
static var _interface: JavaScriptObject
static var _initialization_error := ""

static func initialize() -> void:
	if _initialized:
		return
	_initialized = true
	if not OS.has_feature("web"):
		return
	# 전역 eval이 아니라 고정 Web 런타임의 FS가 보이는 문맥에서 실행한다.
	var result: Variant = JavaScriptBridge.eval(INSTALL_OBSERVER, false)
	if not result is String or not str(result).is_empty():
		_initialization_error = "observer_unavailable" if not result is String else str(result)
		return
	_interface = JavaScriptBridge.get_interface(INTERFACE_NAME)
	if _interface == null:
		_initialization_error = "observer_unavailable"
	elif not OS.is_userfs_persistent():
		_interface.setUnavailable("persistent_storage_unavailable")

# 성공한 로컬 파일 교체·삭제 직후 호출한다. 파일 내용은 JS에 전달하지 않는다.
static func mark_dirty() -> int:
	initialize()
	if not OS.has_feature("web"):
		return 0
	if _interface == null:
		return -1
	var generation := int(_interface.markDirty())
	if bool(_interface.available) and str(_interface.error).is_empty():
		JavaScriptBridge.force_fs_sync()
	return generation

# 원래 엔진의 sync가 실패한 경우에만 2초 간격으로 재요청한다. 직접 syncfs를 중복 실행하지 않는다.
static func retry() -> bool:
	initialize()
	if not OS.has_feature("web") or _interface == null:
		return false
	if not bool(_interface.takeRetry()):
		return false
	JavaScriptBridge.force_fs_sync()
	return true

static func poll() -> Dictionary:
	initialize()
	if not OS.has_feature("web"):
		return {"state": "durable", "generation": 0, "committed_generation": 0, "error": "", "available": true}
	if _interface == null:
		return {"state": "error", "generation": -1, "committed_generation": -1, "error": _initialization_error, "available": false}
	retry()
	return {
		"state": str(_interface.state),
		"generation": int(_interface.generation),
		"committed_generation": int(_interface.committed_generation),
		"error": str(_interface.error),
		"available": bool(_interface.available),
	}

static func status() -> Dictionary:
	return poll()

# 세대를 지정해도 관측 기능이 없거나 실패 상태이면 성공으로 취급하지 않는다.
static func is_durable(generation: int = -1) -> bool:
	var status := poll()
	if status.state == "error" or not status.available:
		return false
	if generation < 0:
		return status.state == "durable"
	return int(status.committed_generation) >= generation

# SaveStore 해제 때는 호출하지 않는다. 최종 앱 종료 때만 관측기와 이탈 경고를 정리한다.
static func shutdown() -> void:
	if _interface != null:
		_interface.shutdown()
	_interface = null
	_initialization_error = ""
	_initialized = false
