// Puts the emulators into a known state once, before any spec runs.
import { seed } from './seed.js';

export default async function globalSetup() {
  await seed();
}
