/* 같은 IndexedDB를 쓰는 협조적 Web 탭은 엔진 시작 전부터 페이지 수명 전체를 잠근다. */
(() => {
	'use strict';

	let initialized = false;
	let writeAllowed = false;
	const messages = {
		en: {
			busy: 'This game is already open in another tab. Close that tab, then try again.',
			unsupported: 'This browser cannot protect saved progress across tabs. Open this page in an up-to-date browser over HTTPS.',
			failed: 'Saved-game protection could not start. Reload this page to try again.',
			retry: 'Try again',
			checking: 'Checking…',
			revoked: 'This game session was suspended or lost saved-game access. Reload the page to safely continue.',
			reload: 'Reload game',
			startupFailed: 'The game could not start. Reload the page to try again.',
		},
		ko: {
			busy: '다른 탭에서 이 게임을 실행 중입니다. 해당 탭을 닫은 뒤 다시 시도해 주세요.',
			unsupported: '이 브라우저에서는 여러 탭 사이의 저장 보호를 사용할 수 없습니다. 최신 브라우저에서 HTTPS 주소로 열어 주세요.',
			failed: '저장 보호를 시작하지 못했습니다. 페이지를 새로고침해 다시 시도해 주세요.',
			retry: '다시 시도',
			checking: '확인 중…',
			revoked: '게임 세션이 중단되었거나 저장 접근 권한을 잃었습니다. 안전하게 계속하려면 페이지를 새로고침해 주세요.',
			reload: '게임 새로고침',
			startupFailed: '게임을 시작하지 못했습니다. 페이지를 새로고침해 다시 시도해 주세요.',
		},
		zh: {
			busy: '此游戏已在另一个标签页中打开。请关闭该标签页后重试。',
			unsupported: '此浏览器无法保护多个标签页之间的存档。请使用最新版浏览器通过 HTTPS 打开此页面。',
			failed: '无法启动存档保护。请刷新页面后重试。',
			retry: '重试',
			checking: '正在检查…',
			revoked: '游戏会话已暂停或失去存档访问权限。请刷新页面后安全地继续游戏。',
			reload: '刷新游戏',
			startupFailed: '无法启动游戏。请刷新页面后重试。',
		},
		ja: {
			busy: 'このゲームは別のタブで開かれています。そのタブを閉じてから、もう一度お試しください。',
			unsupported: 'このブラウザーでは複数のタブ間でセーブデータを保護できません。最新版のブラウザーで HTTPS のページを開いてください。',
			failed: 'セーブデータの保護を開始できませんでした。ページを再読み込みしてください。',
			retry: '再試行',
			checking: '確認中…',
			revoked: 'ゲームセッションが中断されたか、セーブデータへのアクセスを失いました。安全に続けるにはページを再読み込みしてください。',
			reload: 'ゲームを再読み込み',
			startupFailed: 'ゲームを開始できませんでした。ページを再読み込みして、もう一度お試しください。',
		},
	};

	function startWithSessionLock(config, start, display) {
		// 재호출이나 빠른 재시도가 잠금 요청·엔진을 중복 생성하지 않게 한다.
		if (initialized) return;
		initialized = true;
		const language = String(navigator.language || 'en').toLowerCase().split(/[-_]/)[0];
		const text = messages[language] || messages.en;
		let phase = 'ready';
		let retryButton = null;
		let locks;
		let visibilityEpoch = 0;
		let requestEpoch = -1;
		let ownedClientId = '';
		let engineStarted = false;
		let engineSettled = false;
		let waitingForVisibility = false;
		const lifetime = new Promise(() => {});

		function notice(key, action = '') {
			let container = display(text[key]);
			// 게임 시작 후 기본 상태 UI는 제거된다. 해제된 노드에 경고를 쓰지 않는다.
			if (!container || !container.isConnected) {
				container = document.getElementById('rd-session-overlay');
				if (!container) {
					container = document.createElement('div');
					container.id = 'rd-session-overlay';
					container.style.cssText = 'position:fixed;inset:0;z-index:2147483647;display:flex;align-items:center;justify-content:center;box-sizing:border-box;padding:2rem;background:rgba(12,17,26,.96);color:white;font:20px/1.5 sans-serif;text-align:center;';
					container.setAttribute('role', 'dialog');
					container.setAttribute('aria-modal', 'true');
					document.body.appendChild(container);
				}
			}
			const content = document.createElement('div');
			content.id = 'rd-session-notice';
			content.setAttribute('role', action === 'retry' ? 'status' : 'alert');
			content.setAttribute('data-session-state', key);
			content.textContent = text[key];
			container.replaceChildren(content);
			retryButton = null;
			if (action) {
				const button = document.createElement('button');
				button.id = action === 'retry' ? 'rd-session-retry' : 'rd-session-reload';
				button.type = 'button';
				button.textContent = text[action];
				button.style.cssText = 'display:block;margin:1rem auto 0;padding:.75rem 1.25rem;font:inherit;cursor:pointer;';
				button.addEventListener('click', action === 'retry' ? attempt : () => globalThis.location.reload());
				content.appendChild(button);
				if (action === 'retry') retryButton = button;
				button.focus();
			}
		}

		function fail(error) {
			writeAllowed = false;
			phase = 'failed';
			console.error('Saved-game session protection failed:', error);
			try { notice('failed'); }
			catch (displayError) { console.error('Could not show session protection failure:', displayError); }
		}

		function startupFailed(error) {
			writeAllowed = false;
			phase = 'failed';
			console.error('Game startup failed:', error);
			try { notice('startupFailed', 'reload'); }
			catch (displayError) { console.error('Could not show game startup failure:', displayError); }
		}

		function revoke() {
			if (phase === 'revoked') return;
			// 한번 중단된 MEMFS에는 다시 쓰기 권한을 주지 않는다. 새 페이지에서만 복원한다.
			writeAllowed = false;
			phase = 'revoked';
			try { notice('revoked', 'reload'); }
			catch (error) { console.error('Could not show suspended-session notice:', error); }
		}

		function lockFailed(error) {
			if (phase === 'owned' || phase === 'revoked') {
				console.error('Saved-game session ownership ended:', error);
				revoke();
			} else {
				fail(error);
			}
		}

		try {
			if (!config || !Array.isArray(config.persistentPaths) || config.persistentPaths.length !== 1
				|| typeof config.persistentPaths[0] !== 'string' || !config.persistentPaths[0].startsWith('/')
				|| config.serviceWorker || typeof start !== 'function' || typeof display !== 'function') {
				throw new Error('Unexpected Web startup configuration');
			}
			locks = navigator.locks;
			if (!globalThis.isSecureContext || !locks || typeof locks.request !== 'function' || typeof locks.query !== 'function') {
				phase = 'failed';
				notice('unsupported');
				return;
			}
		} catch (error) {
			fail(error);
			return;
		}

		// 실제 DB 경로만 사용한다. URL·버전으로 나누면 같은 저장소에 두 writer가 생긴다.
		const lockName = JSON.stringify(config.persistentPaths);
		// 일반적인 탭 숨김에는 쓰기만 막고, 복귀 시 기존 소유자의 신원을 다시 확인한다.
		document.addEventListener('visibilitychange', () => {
			visibilityEpoch += 1;
			writeAllowed = false;
			if (document.hidden) {
				// 첫 신원 확인/FS populate 도중 숨겨지면 타 탭 신원이나 빈 MEMFS를 채택할 수 있다.
				if ((!ownedClientId || !engineSettled) && (phase === 'requesting' || phase === 'owned')) revoke();
			} else if (phase === 'owned') {
				verifyOwnership();
			} else if (phase === 'ready' && waitingForVisibility) {
				attempt();
			}
		}, true);
		// 실제 동결/이동과 소유권 상실은 영구 차단한다. 오래된 MEMFS로 재획득하지 않는다.
		globalThis.addEventListener('pagehide', revoke, true);
		document.addEventListener('freeze', revoke, true);
		globalThis.addEventListener('pageshow', (event) => { if (event.persisted) revoke(); }, true);

		function verifyOwnership() {
			const epoch = visibilityEpoch;
			writeAllowed = false;
			try {
				Promise.resolve(locks.query()).then((snapshot) => {
					if (phase !== 'owned' || document.hidden || epoch !== visibilityEpoch) return;
					const matches = snapshot && Array.isArray(snapshot.held)
						? snapshot.held.filter((lock) => lock.name === lockName && lock.mode === 'exclusive') : [];
					const clientId = matches.length === 1 ? matches[0].clientId : '';
					if (typeof clientId !== 'string' || !clientId
						|| (ownedClientId ? clientId !== ownedClientId : epoch !== requestEpoch)) {
						revoke();
						return;
					}
					ownedClientId = clientId;
					writeAllowed = true;
					if (!engineStarted) {
						engineStarted = true;
						try {
							Promise.resolve(start()).then(() => {
								if (phase === 'owned') engineSettled = true;
							}, startupFailed);
						}
						catch (error) { startupFailed(error); }
					}
				}).catch(lockFailed);
			} catch (error) {
				lockFailed(error);
			}
		}

		function attempt() {
			if (phase !== 'ready') return;
			if (document.hidden) {
				waitingForVisibility = true;
				return;
			}
			waitingForVisibility = false;
			requestEpoch = visibilityEpoch;
			phase = 'requesting';
			if (retryButton) {
				retryButton.disabled = true;
				retryButton.textContent = text.checking;
			}
			try {
				Promise.resolve(locks.request(lockName, { mode: 'exclusive', ifAvailable: true }, (lock) => {
					if (phase === 'revoked') return lock ? lifetime : undefined;
					if (!lock) {
						phase = 'ready';
						notice('busy', 'retry');
						return;
					}
					phase = 'owned';
					verifyOwnership();
					// startGame 완료는 시작 완료다. 실패·숨김·pagehide에서도 잠금을 풀지 않는다.
					// BFCache에서는 잠금이 사라질 수 있으므로 복원된 기존 런타임의 쓰기는 막는다.
					// 부분 초기화나 마지막 엔진 sync까지 페이지 파괴 전에는 다른 탭에 넘기지 않는다.
					return lifetime;
				})).catch(lockFailed);
			} catch (error) {
				lockFailed(error);
			}
		}
		attempt();
	}

	// 고정 런타임의 IDBFS 경계가 읽을 수 있는 불변 접근자만 추가한다.
	Object.defineProperty(startWithSessionLock, 'writeAllowed', { get: () => writeAllowed && !document.hidden });
	Object.freeze(startWithSessionLock);
	// 저장 내용이나 잠금 해제 API를 외부에 노출하지 않는다.
	Object.defineProperty(globalThis, 'rdStartWithSessionLock', { value: startWithSessionLock });
})();
