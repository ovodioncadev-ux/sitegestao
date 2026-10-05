import { toNextJsHandler } from 'better-auth/next-js';
import { auth } from '@ovo/database/auth';

export const { GET, POST } = toNextJsHandler(auth);
