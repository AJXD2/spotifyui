<script lang="ts">
	import { onMount } from 'svelte';
	import spotify from '$lib/spotify';
	import { Vibrant } from 'node-vibrant/browser';
	import type { PlaybackState, Track, Queue } from '@spotify/web-api-ts-sdk';
	import {
		SkipBack,
		Play,
		Pause,
		SkipForward,
		Shuffle,
		Repeat,
		Repeat1,
		Heart,
		Volume2,
		Volume1,
		VolumeX
	} from '@lucide/svelte';

	// --- State ---
	let loading = $state(true);
	let authenticated = $state(false);
	let pollInterval: ReturnType<typeof setInterval> | null = null;
	let clockInterval: ReturnType<typeof setInterval> | null = null;
	let lastSongId = $state<string | null>(null);
	let playback = $state<PlaybackState | null>(null);
	let playbackImage = $state<string | null>(null);
	let prevImage = $state<string | null>(null);
	let imageTransition = $state(false);
	let deviceId = $state<string>('');

	// Colors from palette
	let bgDark = $state('#08080a');
	let bgMid = $state('#121218');
	let bgAccent = $state('#1a1a2e');
	let glowColor = $state('rgba(100,100,200,0.3)');

	// Progress interpolation
	let syncedProgressMs = $state(0);
	let syncedAt = $state(0);
	let isPlaying = $state(false);
	let durationMs = $state(0);
	let displayProgressMs = $state(0);
	let rafId: number | null = null;

	// Queue
	let upNext = $state<{ name: string; artist: string; image: string }[]>([]);

	// Liked
	let isLiked = $state(false);

	// Clock
	let clockTime = $state('');

	// Volume
	let volumePercent = $state<number | null>(null);

	function tickProgress() {
		if (isPlaying && durationMs > 0) {
			const elapsed = performance.now() - syncedAt;
			displayProgressMs = Math.min(syncedProgressMs + elapsed, durationMs);
		}
		rafId = requestAnimationFrame(tickProgress);
	}

	function syncProgress(state: PlaybackState) {
		syncedProgressMs = state.progress_ms ?? 0;
		syncedAt = performance.now();
		isPlaying = state.is_playing;
		durationMs = state.item?.duration_ms ?? 0;
		displayProgressMs = syncedProgressMs;
	}

	function updateClock() {
		const now = new Date();
		clockTime = now.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
	}

	onMount(() => {
		authenticate();
		rafId = requestAnimationFrame(tickProgress);
		updateClock();
		clockInterval = setInterval(updateClock, 10_000);
		return () => {
			if (pollInterval) clearInterval(pollInterval);
			if (clockInterval) clearInterval(clockInterval);
			if (rafId) cancelAnimationFrame(rafId);
		};
	});

	async function authenticate() {
		try {
			const result = await spotify.authenticate();
			if (result.authenticated) {
				authenticated = true;
				await getCurrentPlayback();
				pollInterval = setInterval(getCurrentPlayback, 2500);
			}
		} catch (e) {
			console.error('Auth failed:', e);
		} finally {
			loading = false;
		}
	}

	async function getCurrentPlayback() {
		try {
			const state = await spotify.player.getCurrentlyPlayingTrack();
			if (!state || !state.item) {
				playback = state;
				return;
			}

			playback = state;
			syncProgress(state);
			if (state.device?.id) deviceId = state.device.id;
			volumePercent = state.device?.volume_percent ?? null;

			if (state.item.id === lastSongId) return;

			// Song changed
			const prevSongId = lastSongId;
			lastSongId = state.item.id;

			if (state.item.type === 'track') {
				const track = state.item as Track;
				const imageUrl = track.album?.images?.[0]?.url;
				if (imageUrl && imageUrl !== playbackImage) {
					prevImage = playbackImage;
					playbackImage = imageUrl;
					imageTransition = true;
					setTimeout(() => (imageTransition = false), 800);

					try {
						const palette = await Vibrant.from(imageUrl).quality(5).getPalette();
						bgDark = palette.DarkMuted?.hex ?? palette.DarkVibrant?.hex ?? '#08080a';
						bgMid = palette.Muted?.hex ?? palette.DarkVibrant?.hex ?? '#121218';
						bgAccent = palette.Vibrant?.hex ?? palette.LightVibrant?.hex ?? '#1a1a2e';
						const glow = palette.Vibrant?.hex ?? palette.LightVibrant?.hex ?? '#6464c8';
						glowColor = glow + '55';
					} catch {
						bgDark = '#08080a';
						bgMid = '#121218';
						bgAccent = '#1a1a2e';
						glowColor = 'rgba(100,100,200,0.3)';
					}
				}

				// Check liked
				try {
					const [liked] = await spotify.currentUser.tracks.hasSavedTracks([state.item.id]);
					isLiked = liked;
				} catch {
					isLiked = false;
				}

				// Fetch queue
				fetchQueue();
			}
		} catch (e) {
			console.error('Playback fetch failed:', e);
		}
	}

	async function fetchQueue() {
		try {
			const q: Queue = await spotify.player.getUsersQueue();
			upNext = q.queue.slice(0, 3).map((item) => {
				const t = item as Track;
				return {
					name: t.name,
					artist: t.artists?.[0]?.name ?? '',
					image: t.album?.images?.[t.album.images.length - 1]?.url ?? ''
				};
			});
		} catch {
			upNext = [];
		}
	}

	function getArtists(item: PlaybackState['item']): string {
		if (!item || item.type !== 'track') return '';
		return (item as Track).artists.map((a) => a.name).join(', ');
	}

	function getAlbum(item: PlaybackState['item']): string {
		if (!item || item.type !== 'track') return '';
		const track = item as Track;
		const year = track.album?.release_date?.split('-')[0] ?? '';
		const name = track.album?.name ?? '';
		return year ? `${name} \u00b7 ${year}` : name;
	}

	function formatTime(ms: number): string {
		const s = Math.floor(ms / 1000);
		const m = Math.floor(s / 60);
		const sec = s % 60;
		return `${m}:${sec.toString().padStart(2, '0')}`;
	}

	async function togglePlay() {
		if (!playback) return;
		try {
			if (playback.is_playing) {
				await spotify.player.pausePlayback(deviceId);
			} else {
				await spotify.player.startResumePlayback(deviceId);
			}
			const nowPlaying = !playback.is_playing;
			playback = { ...playback, is_playing: nowPlaying };
			isPlaying = nowPlaying;
			syncedProgressMs = displayProgressMs;
			syncedAt = performance.now();
		} catch (e) {
			console.error('Toggle play failed:', e);
		}
	}

	async function skipNext() {
		try {
			await spotify.player.skipToNext(deviceId);
			setTimeout(getCurrentPlayback, 400);
		} catch (e) {
			console.error('Skip next failed:', e);
		}
	}

	async function skipPrev() {
		try {
			await spotify.player.skipToPrevious(deviceId);
			setTimeout(getCurrentPlayback, 400);
		} catch (e) {
			console.error('Skip prev failed:', e);
		}
	}

	async function toggleShuffle() {
		if (!playback) return;
		try {
			await spotify.player.togglePlaybackShuffle(!playback.shuffle_state, deviceId);
			playback = { ...playback, shuffle_state: !playback.shuffle_state };
		} catch (e) {
			console.error('Toggle shuffle failed:', e);
		}
	}

	async function cycleRepeat() {
		if (!playback) return;
		const next =
			playback.repeat_state === 'off'
				? 'context'
				: playback.repeat_state === 'context'
					? 'track'
					: 'off';
		try {
			await spotify.player.setRepeatMode(next as 'track' | 'context' | 'off', deviceId);
			playback = { ...playback, repeat_state: next };
		} catch (e) {
			console.error('Cycle repeat failed:', e);
		}
	}

	async function toggleLike() {
		if (!playback?.item?.id) return;
		try {
			if (isLiked) {
				await spotify.currentUser.tracks.removeSavedTracks([playback.item.id]);
			} else {
				await spotify.currentUser.tracks.saveTracks([playback.item.id]);
			}
			isLiked = !isLiked;
		} catch (e) {
			console.error('Toggle like failed:', e);
		}
	}

	async function seekTo(e: MouseEvent) {
		if (!playback?.item?.duration_ms) return;
		const bar = e.currentTarget as HTMLElement;
		const rect = bar.getBoundingClientRect();
		const pct = Math.max(0, Math.min(1, (e.clientX - rect.left) / rect.width));
		const posMs = Math.floor(pct * playback.item.duration_ms);
		try {
			await spotify.player.seekToPosition(posMs, deviceId);
			syncedProgressMs = posMs;
			syncedAt = performance.now();
			displayProgressMs = posMs;
		} catch (e) {
			console.error('Seek failed:', e);
		}
	}
</script>

<svelte:head>
	<link rel="preconnect" href="https://fonts.googleapis.com" />
	<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin="anonymous" />
	<link
		href="https://fonts.googleapis.com/css2?family=Outfit:wght@300;400;500;600;700;800&display=swap"
		rel="stylesheet"
	/>
</svelte:head>

{#if loading}
	<!-- Loading Screen -->
	<div class="kiosk bg-black">
		<div class="flex flex-col items-center gap-5">
			<div class="eq-loader">
				<span></span><span></span><span></span><span></span><span></span>
			</div>
			<p class="font-outfit text-xl font-light tracking-widest text-white/50 uppercase">
				Connecting to Spotify
			</p>
		</div>
	</div>
{:else if authenticated && playback?.item}
	<!-- Now Playing -->
	<div
		class="kiosk-playing"
		style="--bg-dark: {bgDark}; --bg-mid: {bgMid}; --bg-accent: {bgAccent}; --glow: {glowColor};"
	>
		<!-- Background layers -->
		<div class="bg-layer"></div>
		<div class="noise-layer"></div>

		<!-- Top bar -->
		<div class="top-bar">
			<div class="now-playing-label">
				<div class="eq-bars" class:paused={!isPlaying}>
					<span></span><span></span><span></span><span></span>
				</div>
				<span class="label-text">NOW PLAYING</span>
			</div>

			<div class="top-right">
				{#if volumePercent != null}
					<div class="volume-pill">
						{#if volumePercent === 0}
							<VolumeX size={14} />
						{:else if volumePercent < 50}
							<Volume1 size={14} />
						{:else}
							<Volume2 size={14} />
						{/if}
						<span>{volumePercent}%</span>
					</div>
				{/if}
				<div class="clock">{clockTime}</div>
			</div>
		</div>

		<!-- Main content -->
		<div class="main-content">
			<!-- Album Art -->
			<div class="art-container">
				{#if playbackImage}
					<div class="art-glow" style="background: {glowColor};"></div>
					<img
						src={playbackImage}
						alt="Album Cover"
						class="album-art"
						class:art-entering={imageTransition}
					/>
				{:else}
					<div class="album-art-placeholder">
						<span>?</span>
					</div>
				{/if}
			</div>

			<!-- Track Info Panel -->
			<div class="info-panel">
				<div class="track-meta">
					<h1 class="track-title">{playback.item.name}</h1>
					<p class="track-artist">{getArtists(playback.item)}</p>
					<p class="track-album">{getAlbum(playback.item)}</p>
				</div>

				<!-- Progress -->
				{#if durationMs > 0}
					{@const progress = (displayProgressMs / durationMs) * 100}
					<!-- svelte-ignore a11y_click_events_have_key_events -->
					<!-- svelte-ignore a11y_no_static_element_interactions -->
					<div class="progress-wrap" onclick={seekTo}>
						<div class="progress-track">
							<div class="progress-fill" style="width: {progress}%;"></div>
							<div class="progress-knob" style="left: {progress}%;"></div>
						</div>
						<div class="progress-times">
							<span>{formatTime(displayProgressMs)}</span>
							<span>{formatTime(durationMs)}</span>
						</div>
					</div>
				{/if}

				<!-- Controls -->
				<div class="controls-row">
					<button
						class="ctrl-btn-sm"
						class:ctrl-active={playback.shuffle_state}
						onclick={toggleShuffle}
						aria-label="Shuffle"
					>
						<Shuffle size={20} />
					</button>

					<button class="ctrl-btn" onclick={skipPrev} aria-label="Previous">
						<SkipBack size={28} fill="currentColor" />
					</button>

					<button class="ctrl-btn-main" onclick={togglePlay} aria-label="Play/Pause">
						{#if isPlaying}
							<Pause size={36} fill="currentColor" />
						{:else}
							<Play size={36} fill="currentColor" style="margin-left: 3px;" />
						{/if}
					</button>

					<button class="ctrl-btn" onclick={skipNext} aria-label="Next">
						<SkipForward size={28} fill="currentColor" />
					</button>

					<button
						class="ctrl-btn-sm"
						class:ctrl-active={playback.repeat_state !== 'off'}
						onclick={cycleRepeat}
						aria-label="Repeat"
					>
						{#if playback.repeat_state === 'track'}
							<Repeat1 size={20} />
						{:else}
							<Repeat size={20} />
						{/if}
					</button>

					<button
						class="ctrl-btn-sm like-btn"
						class:liked={isLiked}
						onclick={toggleLike}
						aria-label="Like"
					>
						<Heart size={20} fill={isLiked ? 'currentColor' : 'none'} />
					</button>
				</div>
			</div>
		</div>

		<!-- Queue Strip -->
		{#if upNext.length > 0}
			<div class="queue-strip">
				<span class="queue-label">UP NEXT</span>
				<div class="queue-items">
					{#each upNext as track}
						<div class="queue-item">
							{#if track.image}
								<img src={track.image} alt="" class="queue-thumb" />
							{/if}
							<div class="queue-text">
								<span class="queue-track-name">{track.name}</span>
								<span class="queue-track-artist">{track.artist}</span>
							</div>
						</div>
					{/each}
				</div>
			</div>
		{/if}
	</div>
{:else}
	<!-- Idle / Offline Screensaver -->
	<div class="screensaver">
		<div class="screensaver-bg"></div>
		<div class="screensaver-noise"></div>
		<div class="screensaver-stars"></div>
		<div class="screensaver-orbit screensaver-orbit-a"></div>
		<div class="screensaver-orbit screensaver-orbit-b"></div>
		<div class="screensaver-glow"></div>
		<div class="dvd-bounce-x">
			<div class="dvd-bounce-y">
				<div class="dvd-logo">
					<svg class="dvd-logo-icon" viewBox="0 0 496 512" role="img" aria-label="Spotify icon">
						<path
							fill="#1ed760"
							d="M248 8C111.1 8 0 119.1 0 256s111.1 248 248 248 248-111.1 248-248S384.9 8 248 8Z"
						/>
						<path
							fill="#111"
							d="M406.6 231.1c-5.2 0-8.4-1.3-12.9-3.9-71.2-42.5-198.5-52.7-280.9-29.7-3.6 1-8.1 2.6-12.9 2.6-13.2 0-23.3-10.3-23.3-23.6 0-13.6 8.4-21.3 17.4-23.9 35.2-10.3 74.6-15.2 117.5-15.2 73 0 149.5 15.2 205.4 47.8 7.8 4.5 12.9 10.7 12.9 22.6 0 13.6-11 23.3-23.2 23.3zm-31 76.2c-5.2 0-8.7-2.3-12.3-4.2-62.5-37-155.7-51.9-238.6-29.4-4.8 1.3-7.4 2.6-11.9 2.6-10.7 0-19.4-8.7-19.4-19.4s5.2-17.8 15.5-20.7c27.8-7.8 56.2-13.6 97.8-13.6 64.9 0 127.6 16.1 177 45.5 8.1 4.8 11.3 11 11.3 19.7-.1 10.8-8.5 19.5-19.4 19.5zm-26.9 65.6c-4.2 0-6.8-1.3-10.7-3.6-62.4-37.6-135-39.2-206.7-24.5-3.9 1-9 2.6-11.9 2.6-9.7 0-15.8-7.7-15.8-15.8 0-10.3 6.1-15.2 13.6-16.8 81.9-18.1 165.6-16.5 237 26.2 6.1 3.9 9.7 7.4 9.7 16.5s-7.1 15.4-15.2 15.4z"
						/>
					</svg>
				</div>
			</div>
		</div>

		<div class="screensaver-content">
			<div class="screensaver-badge">{authenticated ? 'Idle mode' : 'Offline mode'}</div>

			<div class="eq-bars" style="height: 30px;">
				<span></span><span></span><span></span><span></span>
			</div>

			<p class="screensaver-title">
				{authenticated ? 'Nothing is playing' : 'Could not connect to Spotify'}
			</p>
			<p class="screensaver-subtitle">
				{authenticated
					? 'Start playback on any Spotify device to wake the display.'
					: 'Reconnect to Spotify to resume live playback.'}
			</p>
		</div>
	</div>
{/if}

<style>
	/* ==================== FOUNDATIONS ==================== */

	:global(.font-outfit) {
		font-family: 'Outfit', sans-serif;
	}

	.kiosk {
		font-family: 'Outfit', sans-serif;
		display: flex;
		align-items: center;
		justify-content: center;
		width: 100vw;
		height: 100vh;
		overflow: hidden;
		color: white;
	}

	.kiosk-playing {
		font-family: 'Outfit', sans-serif;
		position: relative;
		display: flex;
		flex-direction: column;
		width: 100vw;
		height: 100vh;
		overflow: hidden;
		color: white;
	}

	/* ==================== BACKGROUND ==================== */

	.bg-layer {
		position: absolute;
		inset: 0;
		background: linear-gradient(
			145deg,
			var(--bg-dark) 0%,
			var(--bg-mid) 55%,
			var(--bg-accent) 100%
		);
		transition: background 2s ease;
		z-index: 0;
	}

	.noise-layer {
		position: absolute;
		inset: 0;
		opacity: 0.03;
		background-image: url("data:image/svg+xml,%3Csvg viewBox='0 0 256 256' xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.9' numOctaves='4' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)'/%3E%3C/svg%3E");
		background-size: 128px 128px;
		z-index: 1;
		pointer-events: none;
	}

	/* ==================== TOP BAR ==================== */

	.top-bar {
		position: relative;
		z-index: 2;
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: 12px 24px;
		flex-shrink: 0;
	}

	.now-playing-label {
		display: flex;
		align-items: center;
		gap: 10px;
	}

	.label-text {
		font-size: 11px;
		font-weight: 600;
		letter-spacing: 0.2em;
		color: rgba(255, 255, 255, 0.45);
	}

	.top-right {
		display: flex;
		align-items: center;
		gap: 16px;
	}

	.volume-pill {
		display: flex;
		align-items: center;
		gap: 5px;
		padding: 4px 10px;
		border-radius: 99px;
		background: rgba(255, 255, 255, 0.06);
		color: rgba(255, 255, 255, 0.4);
		font-size: 12px;
		font-weight: 500;
	}

	.clock {
		font-size: 14px;
		font-weight: 500;
		color: rgba(255, 255, 255, 0.35);
		letter-spacing: 0.05em;
		font-variant-numeric: tabular-nums;
	}

	/* ==================== EQ BARS ==================== */

	.eq-bars {
		display: flex;
		align-items: flex-end;
		gap: 2px;
		height: 16px;
	}

	.eq-bars span {
		width: 3px;
		border-radius: 2px;
		background: #1db954;
		animation: eq 1s ease-in-out infinite;
	}
	.eq-bars span:nth-child(1) {
		animation-delay: 0s;
		height: 60%;
	}
	.eq-bars span:nth-child(2) {
		animation-delay: 0.15s;
		height: 100%;
	}
	.eq-bars span:nth-child(3) {
		animation-delay: 0.3s;
		height: 40%;
	}
	.eq-bars span:nth-child(4) {
		animation-delay: 0.45s;
		height: 80%;
	}

	.eq-bars.paused span {
		animation-play-state: paused;
		height: 20% !important;
		opacity: 0.3;
	}

	@keyframes eq {
		0%,
		100% {
			height: 20%;
		}
		50% {
			height: 100%;
		}
	}

	/* Loading eq */
	.eq-loader {
		display: flex;
		align-items: flex-end;
		gap: 4px;
		height: 40px;
	}
	.eq-loader span {
		width: 5px;
		border-radius: 3px;
		background: #1db954;
		animation: eq 0.8s ease-in-out infinite;
	}
	.eq-loader span:nth-child(1) {
		animation-delay: 0s;
	}
	.eq-loader span:nth-child(2) {
		animation-delay: 0.1s;
	}
	.eq-loader span:nth-child(3) {
		animation-delay: 0.2s;
	}
	.eq-loader span:nth-child(4) {
		animation-delay: 0.3s;
	}
	.eq-loader span:nth-child(5) {
		animation-delay: 0.4s;
	}

	/* ==================== MAIN CONTENT ==================== */

	.main-content {
		position: relative;
		z-index: 2;
		display: flex;
		flex: 1;
		min-height: 0;
		padding: 0 24px;
		gap: 28px;
	}

	/* ==================== ALBUM ART ==================== */

	.art-container {
		position: relative;
		display: flex;
		align-items: center;
		justify-content: center;
		flex-shrink: 0;
		padding: 8px 0 8px 8px;
	}

	.art-glow {
		position: absolute;
		inset: 20px;
		border-radius: 20px;
		filter: blur(40px);
		opacity: 0.5;
		transition: background 2s ease;
		z-index: 0;
	}

	.album-art {
		position: relative;
		z-index: 1;
		height: min(52vh, 40vw);
		width: min(52vh, 40vw);
		border-radius: 16px;
		object-fit: cover;
		box-shadow:
			0 8px 40px rgba(0, 0, 0, 0.5),
			0 0 80px var(--glow);
		transition:
			box-shadow 2s ease,
			opacity 0.6s ease,
			transform 0.6s ease;
	}

	.album-art.art-entering {
		animation: art-in 0.6s ease-out;
	}

	@keyframes art-in {
		0% {
			opacity: 0;
			transform: scale(0.92);
		}
		100% {
			opacity: 1;
			transform: scale(1);
		}
	}

	.album-art-placeholder {
		height: min(52vh, 40vw);
		width: min(52vh, 40vw);
		border-radius: 16px;
		background: rgba(255, 255, 255, 0.04);
		display: flex;
		align-items: center;
		justify-content: center;
		font-size: 48px;
		color: rgba(255, 255, 255, 0.1);
	}

	/* ==================== INFO PANEL ==================== */

	.info-panel {
		flex: 1;
		min-width: 0;
		display: flex;
		flex-direction: column;
		justify-content: center;
		gap: 16px;
		padding-right: 8px;
	}

	.track-meta {
		min-width: 0;
	}

	.track-title {
		font-size: 28px;
		font-weight: 700;
		line-height: 1.15;
		color: white;
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
		margin: 0;
	}

	.track-artist {
		font-size: 18px;
		font-weight: 400;
		color: rgba(255, 255, 255, 0.55);
		margin: 4px 0 0;
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}

	.track-album {
		font-size: 13px;
		font-weight: 400;
		color: rgba(255, 255, 255, 0.28);
		margin: 2px 0 0;
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}

	/* ==================== PROGRESS ==================== */

	.progress-wrap {
		width: 100%;
		padding: 4px 0;
		cursor: pointer;
		-webkit-tap-highlight-color: transparent;
	}

	.progress-track {
		position: relative;
		height: 5px;
		border-radius: 99px;
		background: rgba(255, 255, 255, 0.1);
	}

	.progress-fill {
		height: 100%;
		border-radius: 99px;
		background: rgba(255, 255, 255, 0.75);
		transition: none;
	}

	.progress-knob {
		position: absolute;
		top: 50%;
		width: 14px;
		height: 14px;
		border-radius: 50%;
		background: white;
		transform: translate(-50%, -50%);
		box-shadow: 0 0 6px rgba(0, 0, 0, 0.4);
		transition: none;
	}

	.progress-times {
		display: flex;
		justify-content: space-between;
		margin-top: 6px;
		font-size: 12px;
		font-weight: 500;
		color: rgba(255, 255, 255, 0.35);
		font-variant-numeric: tabular-nums;
	}

	/* ==================== CONTROLS ==================== */

	.controls-row {
		display: flex;
		align-items: center;
		justify-content: center;
		gap: 8px;
	}

	.ctrl-btn {
		display: flex;
		align-items: center;
		justify-content: center;
		width: 56px;
		height: 56px;
		border-radius: 50%;
		background: rgba(255, 255, 255, 0.07);
		color: rgba(255, 255, 255, 0.85);
		border: none;
		-webkit-tap-highlight-color: transparent;
		transition:
			transform 0.12s ease,
			background 0.12s ease;
	}
	.ctrl-btn:active {
		transform: scale(0.9);
		background: rgba(255, 255, 255, 0.15);
	}

	.ctrl-btn-main {
		display: flex;
		align-items: center;
		justify-content: center;
		width: 72px;
		height: 72px;
		border-radius: 50%;
		background: rgba(255, 255, 255, 0.15);
		color: white;
		border: 2px solid rgba(255, 255, 255, 0.15);
		-webkit-tap-highlight-color: transparent;
		transition:
			transform 0.12s ease,
			background 0.12s ease;
	}
	.ctrl-btn-main:active {
		transform: scale(0.9);
		background: rgba(255, 255, 255, 0.25);
	}

	.ctrl-btn-sm {
		display: flex;
		align-items: center;
		justify-content: center;
		width: 42px;
		height: 42px;
		border-radius: 50%;
		background: transparent;
		color: rgba(255, 255, 255, 0.3);
		border: none;
		-webkit-tap-highlight-color: transparent;
		transition:
			transform 0.12s ease,
			color 0.15s ease;
	}
	.ctrl-btn-sm:active {
		transform: scale(0.88);
	}
	.ctrl-btn-sm.ctrl-active {
		color: #1db954;
	}

	.like-btn.liked {
		color: #e74c6f;
	}

	/* ==================== QUEUE STRIP ==================== */

	.queue-strip {
		position: relative;
		z-index: 2;
		display: flex;
		align-items: center;
		gap: 16px;
		padding: 8px 24px 12px;
		flex-shrink: 0;
		border-top: 1px solid rgba(255, 255, 255, 0.05);
	}

	.queue-label {
		font-size: 10px;
		font-weight: 600;
		letter-spacing: 0.15em;
		color: rgba(255, 255, 255, 0.25);
		white-space: nowrap;
		flex-shrink: 0;
	}

	.queue-items {
		display: flex;
		gap: 16px;
		overflow: hidden;
		flex: 1;
	}

	.queue-item {
		display: flex;
		align-items: center;
		gap: 8px;
		min-width: 0;
		flex-shrink: 0;
		max-width: 200px;
	}

	.queue-thumb {
		width: 32px;
		height: 32px;
		border-radius: 6px;
		object-fit: cover;
		flex-shrink: 0;
	}

	.queue-text {
		display: flex;
		flex-direction: column;
		min-width: 0;
	}

	.queue-track-name {
		font-size: 12px;
		font-weight: 500;
		color: rgba(255, 255, 255, 0.5);
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}

	.queue-track-artist {
		font-size: 11px;
		font-weight: 400;
		color: rgba(255, 255, 255, 0.25);
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}

	/* ==================== IDLE SCREENSAVER ==================== */

	.screensaver {
		position: relative;
		display: flex;
		align-items: center;
		justify-content: center;
		width: 100vw;
		height: 100vh;
		overflow: hidden;
		background: #050507;
		color: white;
	}

	.screensaver-bg {
		position: absolute;
		inset: -20%;
		background:
			radial-gradient(circle at 20% 20%, rgba(29, 185, 84, 0.16), transparent 45%),
			radial-gradient(circle at 80% 30%, rgba(116, 92, 255, 0.2), transparent 44%),
			radial-gradient(circle at 50% 80%, rgba(52, 174, 255, 0.16), transparent 48%),
			linear-gradient(135deg, #040406 0%, #0b0b12 50%, #050509 100%);
		filter: saturate(115%);
		animation: screensaverDrift 22s ease-in-out infinite alternate;
		z-index: 0;
	}

	.screensaver-noise {
		position: absolute;
		inset: 0;
		opacity: 0.05;
		background-image: url("data:image/svg+xml,%3Csvg viewBox='0 0 256 256' xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='1.1' numOctaves='3' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)'/%3E%3C/svg%3E");
		background-size: 128px 128px;
		animation: screensaverNoise 0.25s steps(2) infinite;
		z-index: 1;
		pointer-events: none;
	}

	.screensaver-stars {
		position: absolute;
		inset: -25%;
		background-image:
			radial-gradient(circle, rgba(255, 255, 255, 0.5) 1px, transparent 1.5px),
			radial-gradient(circle, rgba(255, 255, 255, 0.3) 1px, transparent 1.5px);
		background-size:
			120px 120px,
			170px 170px;
		background-position:
			0 0,
			40px 70px;
		opacity: 0.4;
		animation: screensaverStars 60s linear infinite;
		z-index: 2;
		pointer-events: none;
	}

	.screensaver-orbit {
		position: absolute;
		border: 1px solid rgba(255, 255, 255, 0.08);
		border-radius: 999px;
		filter: blur(0.3px);
		z-index: 3;
	}

	.screensaver-orbit-a {
		width: min(70vw, 640px);
		height: min(70vw, 640px);
		animation: screensaverSpin 40s linear infinite;
	}

	.screensaver-orbit-b {
		width: min(54vw, 500px);
		height: min(54vw, 500px);
		animation: screensaverSpinReverse 28s linear infinite;
	}

	.screensaver-glow {
		position: absolute;
		width: min(34vw, 320px);
		height: min(34vw, 320px);
		border-radius: 50%;
		background: radial-gradient(
			circle,
			rgba(29, 185, 84, 0.35) 0%,
			rgba(93, 120, 255, 0.22) 45%,
			rgba(0, 0, 0, 0) 72%
		);
		filter: blur(14px);
		animation: screensaverPulse 4.8s ease-in-out infinite;
		z-index: 4;
	}

	.dvd-bounce-x {
		position: absolute;
		inset: 24px;
		animation: dvdBounceX 17s linear infinite alternate;
		z-index: 4;
		pointer-events: none;
	}

	.dvd-bounce-y {
		position: absolute;
		animation: dvdBounceY 12.8s linear infinite alternate;
	}

	.dvd-logo {
		display: inline-block;
		filter: drop-shadow(0 0 16px rgba(30, 215, 96, 0.45)) drop-shadow(0 0 26px rgba(0, 0, 0, 0.45));
		animation: dvdHueShift 8s linear infinite;
	}

	.dvd-logo-icon {
		display: block;
		width: clamp(48px, 6vw, 72px);
		height: clamp(48px, 6vw, 72px);
	}

	.screensaver-content {
		position: relative;
		z-index: 5;
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 16px;
		max-width: min(84vw, 760px);
		padding: 32px 20px;
		text-align: center;
	}

	.screensaver-badge {
		padding: 6px 14px;
		border-radius: 999px;
		background: rgba(255, 255, 255, 0.08);
		border: 1px solid rgba(255, 255, 255, 0.14);
		font-size: 12px;
		font-weight: 500;
		letter-spacing: 0.11em;
		text-transform: uppercase;
		color: rgba(255, 255, 255, 0.78);
		backdrop-filter: blur(6px);
	}

	.screensaver-title {
		margin: 0;
		font-size: clamp(30px, 4.2vw, 58px);
		font-weight: 700;
		letter-spacing: -0.015em;
		color: rgba(255, 255, 255, 0.94);
		text-shadow: 0 0 28px rgba(0, 0, 0, 0.35);
	}

	.screensaver-subtitle {
		margin: 0;
		max-width: min(88vw, 620px);
		font-size: clamp(13px, 1.6vw, 18px);
		font-weight: 400;
		color: rgba(255, 255, 255, 0.56);
		letter-spacing: 0.01em;
	}

	@keyframes screensaverDrift {
		0% {
			transform: translate3d(-1%, -2%, 0) scale(1);
		}
		100% {
			transform: translate3d(2%, 2%, 0) scale(1.06);
		}
	}

	@keyframes screensaverNoise {
		0% {
			transform: translate(0, 0);
		}
		100% {
			transform: translate(2px, -1px);
		}
	}

	@keyframes screensaverStars {
		0% {
			transform: translate3d(0, 0, 0) rotate(0deg);
		}
		100% {
			transform: translate3d(-130px, -90px, 0) rotate(6deg);
		}
	}

	@keyframes screensaverSpin {
		0% {
			transform: rotate(0deg);
		}
		100% {
			transform: rotate(360deg);
		}
	}

	@keyframes screensaverSpinReverse {
		0% {
			transform: rotate(360deg);
		}
		100% {
			transform: rotate(0deg);
		}
	}

	@keyframes screensaverPulse {
		0%,
		100% {
			transform: scale(0.86);
			opacity: 0.72;
		}
		50% {
			transform: scale(1.08);
			opacity: 1;
		}
	}

	@keyframes dvdBounceX {
		from {
			transform: translateX(0);
		}
		to {
			transform: translateX(calc(100vw - 150px));
		}
	}

	@keyframes dvdBounceY {
		from {
			transform: translateY(0);
		}
		to {
			transform: translateY(calc(100vh - 150px));
		}
	}

	@keyframes dvdHueShift {
		from {
			filter: hue-rotate(0deg);
		}
		to {
			filter: hue-rotate(360deg);
		}
	}

	@media (prefers-reduced-motion: reduce) {
		.dvd-bounce-x,
		.dvd-bounce-y,
		.screensaver-bg,
		.screensaver-stars,
		.screensaver-glow,
		.eq-bars span {
			animation: none !important;
		}
	}
</style>
