import { SpotifyApi } from '@spotify/web-api-ts-sdk';
import { env } from '$env/dynamic/public';

const scopes = [
	'user-read-playback-state',
	'user-modify-playback-state',
	'user-read-recently-played',
	'user-read-currently-playing',
	'user-follow-read',
	'user-library-read',
	'user-library-modify',
	'user-read-email',
	'user-read-private',
	'playlist-read-private',
	'playlist-read-collaborative'
];

const redirectUri = `${window.location.origin}/callback`;

const spotify = SpotifyApi.withUserAuthorization(
	env.PUBLIC_SPOTIFY_CLIENT_ID,
	redirectUri,
	scopes
);

export default spotify;