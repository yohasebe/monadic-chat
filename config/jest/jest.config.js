// Consolidated Jest config. Behavior switches by env JEST_MODE.
// - default (mock-friendly): JEST_MODE unset or any value other than 'no-mock'
// - no-mock UI tests: JEST_MODE='no-mock'

const path = require('path');

const defaultConfig = {
  rootDir: path.resolve(__dirname, '../..'),
  testEnvironment: 'jsdom',
  testMatch: ['**/test/**/*.test.js'],
  collectCoverage: false, // Off by default; use `npm run test:coverage`
  // The babel/istanbul provider breaks because package.json overrides pin
  // glob/minimatch to v10, which test-exclude cannot consume. V8 coverage
  // does not use test-exclude, so it works with the overrides in place.
  coverageProvider: 'v8',
  collectCoverageFrom: [
    'docker/services/ruby/public/js/monadic/**/*.js',
    'docker/services/ruby/public/js/monadic.js',
    '!**/node_modules/**'
  ],
  coverageDirectory: 'coverage',
  // Conservative floor: ~10 points below the measured baseline
  // (35.36 stmts / 66.57 branch / 72.3 funcs / 35.36 lines as of 2026-07).
  coverageThreshold: {
    global: {
      statements: 25,
      branches: 56,
      functions: 62,
      lines: 25
    }
  },
  transform: {},
  testPathIgnorePatterns: ['/node_modules/'],
  setupFilesAfterEnv: ['<rootDir>/test/setup.js'],
  moduleDirectories: ['node_modules', 'docker/services/ruby/public/js'],
  moduleNameMapper: {
    '^monadic/(.*)$': '<rootDir>/docker/services/ruby/public/js/monadic/$1',
    '^monadic$': '<rootDir>/docker/services/ruby/public/js/monadic.js'
  },
  globals: {
    '__DEV__': true
  }
};

const noMockConfig = {
  rootDir: path.resolve(__dirname, '../..'),
  testEnvironment: 'jsdom',
  testMatch: ['**/test/frontend/no-mock/**/*.test.js'],
  setupFilesAfterEnv: [], // No global mocks
  moduleNameMapper: {
    '\\.(css|less|scss|sass)$': '<rootDir>/test/mocks/styleMock.js'
  },
  testPathIgnorePatterns: [
    '/node_modules/',
    '/test/frontend/[^/]+\\.test\\.js$' // Ignore old mock-based tests
  ],
  coveragePathIgnorePatterns: [
    '/node_modules/',
    '/test/frontend/support/',
    '/test/helpers.js',
    '/test/setup.js'
  ],
  collectCoverageFrom: [
    'docker/services/ruby/public/js/**/*.js',
    '!docker/services/ruby/public/js/vendor/**',
    '!docker/services/ruby/public/js/**/*.min.js'
  ],
  transformIgnorePatterns: ['node_modules/(?!(ws)/)'],
  testTimeout: 10000,
  verbose: true
};

const mode = (process.env.JEST_MODE || '').toLowerCase();
module.exports = mode === 'no-mock' ? noMockConfig : defaultConfig;
