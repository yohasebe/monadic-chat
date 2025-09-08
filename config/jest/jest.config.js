// Consolidated Jest config. Behavior switches by env JEST_MODE.
// - default (mock-friendly): JEST_MODE unset or any value other than 'no-mock'
// - no-mock UI tests: JEST_MODE='no-mock'

const defaultConfig = {
  testEnvironment: 'jsdom',
  testMatch: ['**/test/**/*.test.js'],
  collectCoverage: false, // Temporarily disable coverage to avoid minimatch error
  collectCoverageFrom: [
    'docker/services/ruby/public/js/monadic/**/*.js',
    'docker/services/ruby/public/js/monadic.js',
    '!**/node_modules/**'
  ],
  coverageDirectory: 'coverage',
  transform: {},
  testPathIgnorePatterns: ['/node_modules/'],
  setupFilesAfterEnv: ['./test/setup.js'],
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
