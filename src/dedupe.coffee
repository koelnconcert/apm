path = require 'path'

async = require 'async'
_ = require 'underscore-plus'
optimist = require 'optimist'

config = require './config'
Command = require './command'
fs = require './fs'

module.exports =
class Dedupe extends Command
  @commandNames: ['dedupe']

  constructor: ->
    @atomDirectory = config.getAtomDirectory()
    @atomPackagesDirectory = path.join(@atomDirectory, 'packages')
    @atomNodeDirectory = path.join(@atomDirectory, '.node-gyp')
    @atomNpmPath = require.resolve('npm/bin/npm-cli')
    @atomNodeGypPath = require.resolve('node-gyp/bin/node-gyp')

  parseOptions: (argv) ->
    options = optimist(argv)
    options.usage """

      Usage: apm dedupe [<package_name>...]

      Reduce duplication in the node_modules folder in the current directory.

      This command is experimental.
    """
    options.alias('h', 'help').describe('help', 'Print this usage message')

  installNode: (callback) ->
    installNodeArgs = ['install']
    installNodeArgs.push("--target=#{config.getNodeVersion()}")
    installNodeArgs.push("--dist-url=#{config.getNodeUrl()}")
    installNodeArgs.push('--arch=ia32')

    env = _.extend({}, process.env, HOME: @atomNodeDirectory)
    env.USERPROFILE = env.HOME if config.isWin32()

    fs.makeTreeSync(@atomDirectory)
    @fork @atomNodeGypPath, installNodeArgs, {env, cwd: @atomDirectory}, (code, stderr='', stdout='') ->
      if code is 0
        callback()
      else
        callback("#{stdout}\n#{stderr}")

  getVisualStudioFlags: ->
    return null unless config.isWin32()

    if vsVersion = config.getInstalledVisualStudioFlag()
      "--msvs_version=#{vsVersion}"
    else
      throw new Error('You must have Visual Studio 2010 or 2012 installed')

  dedupeModules: (options, callback) ->
    process.stdout.write 'Deduping modules '

    @forkDedupeCommand options, (code, stderr='', stdout='') =>
      if code is 0
        process.stdout.write '\u2713\n'.green
        callback()
      else
        process.stdout.write '\u2717\n'.red
        callback("#{stdout}\n#{stderr}")

  forkDedupeCommand: (options, callback) ->
    dedupeArgs = ['--globalconfig', config.getGlobalConfigPath(), '--userconfig', config.getUserConfigPath(), 'dedupe']
    dedupeArgs.push("--target=#{config.getNodeVersion()}")
    dedupeArgs.push('--arch=ia32')
    dedupeArgs.push('--silent') if options.argv.silent
    dedupeArgs.push('--quiet') if options.argv.quiet

    if vsArgs = @getVisualStudioFlags()
      dedupeArgs.push(vsArgs)

    dedupeArgs.push(packageName) for packageName in options.argv._

    env = _.extend({}, process.env, HOME: @atomNodeDirectory)
    env.USERPROFILE = env.HOME if config.isWin32()
    dedupeOptions = {env}
    dedupeOptions.cwd = options.cwd if options.cwd

    @fork(@atomNpmPath, dedupeArgs, dedupeOptions, callback)

  createAtomDirectories: ->
    fs.makeTreeSync(@atomDirectory)
    fs.makeTreeSync(@atomNodeDirectory)

  run: (options) ->
    {callback} = options
    options = @parseOptions(options.commandArgs)

    @createAtomDirectories()

    commands = []
    commands.push (callback) => @installNode(callback)
    commands.push (callback) => @dedupeModules(options, callback)
    async.waterfall commands, callback
