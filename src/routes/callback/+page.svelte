<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import spotify from '$lib/spotify';

	let error = $state<string | null>(null);

	onMount(async () => {
		try {
			const { authenticated } = await spotify.authenticate();
			if (authenticated) {
				goto('/');
			} else {
				error = 'Authentication was not completed. Please try again.';
			}
		} catch (e) {
			console.error('Spotify authentication failed:', e);
			error = e instanceof Error ? e.message : 'Authentication failed';
		}
	});
</script>

<div class="flex min-h-screen items-center justify-center">
	{#if error}
		<div class="text-center">
			<p class="text-error text-lg">{error}</p>
			<a href="/" class="btn btn-primary mt-4">Try Again</a>
		</div>
	{:else}
		<span class="loading loading-spinner loading-lg"></span>
		<p class="ml-4 text-lg">Authenticating with Spotify...</p>
	{/if}
</div>
