require 'spec_helper'

RSpec.describe Puppeteer::Launcher do
  describe 'Browser#disconnect', puppeteer: :browser do
    context 'with one-style page' do
      sinatra do
        get('/one-style.html') do
          "<link rel='stylesheet' href='./one-style.css'><div>hello, world!</div>"
        end
      end

      it 'should reject navigation when browser closes' do
        remote = Puppeteer.connect(browser_ws_endpoint: browser.ws_endpoint)
        page = remote.new_page

        # try to disconnect remote connection exactly during loading css.
        wait_for_css = resolvable_future
        sinatra.get('/one-style.css') do
          wait_for_css.fulfill(nil)
          sleep 30
          "body { background-color: pink; }"
        end
        navigation_promise = future { page.goto('http://127.0.0.1:4567/one-style.html') }
        wait_for_css.then { sleep 0.004; remote.disconnect }

        expect { await navigation_promise }.to raise_error(/Navigation failed because browser has disconnected!/)
        browser.close
      end
    end

    it 'should reject wait_for_selector when browser closes' do
      remote = Puppeteer.connect(browser_ws_endpoint: browser.ws_endpoint)
      page = remote.new_page

      watchdog = page.async_wait_for_selector('div')
      remote.disconnect

      expect { await watchdog }.to raise_error(/Protocol error/)
      browser.close
    end
  end

  describe 'Browser#close', puppeteer: :browser do
    sinatra do
      get('/empty.html') { "" }
    end

    it 'should terminate network waiters' do
      remote = Puppeteer.connect(browser_ws_endpoint: browser.ws_endpoint)

      new_page = remote.new_page

      wait_for_request = new_page.async_wait_for_request(url: 'http://localhost:4567/empty.html')
      wait_for_response = new_page.async_wait_for_response(url: 'http://localhost:4567/empty.html')

      browser.close
      expect { await wait_for_request }.to raise_error(/Target Closed/)
      expect { await wait_for_response }.to raise_error(/Target Closed/)
    end
  end

  describe 'Puppeteer#launch', puppeteer: :browser do
    it 'should reject all promises when browser is closed' do
      page = browser.new_page
      never_resolves = page.async_evaluate('() => new Promise(() => {})')

      sleep 0.004 # sleep a bit after page is created, before closing it.

      browser.close
      expect { await never_resolves }.to raise_error(/Protocol error/)
    end
  end

  describe 'Puppeteer#launch' do
    it 'should reject if executable path is invalid' do
      options = default_launch_options.merge(
        executable_path: 'random-invalid-path',
      )

      expect { Puppeteer.launch(**options) }.to raise_error(/Failed to launch/)
    end

    it 'user_data_dir option' do
      Dir.mktmpdir do |user_data_dir|
        options = default_launch_options.merge(
          user_data_dir: user_data_dir,
        )

        Puppeteer.launch(**options) do |browser|
          # Open a page to make sure its functional.
          browser.new_page
          expect(Dir[File.join(user_data_dir, "*")].count).to be > 0
        end
        expect(Dir[File.join(user_data_dir, "*")].count).to be > 0
      end
    end

    it 'user_data_dir argument' do
      Dir.mktmpdir do |user_data_dir|
        options = default_launch_options.dup

        default_launch_option_args = default_launch_options[:args] || []
        if Puppeteer.env.firefox?
          options[:args] = default_launch_option_args + [
            '-profile',
            user_data_dir,
          ]
        else
          options[:args] = default_launch_option_args + [
            "--user-data-dir=#{user_data_dir}",
          ]
        end

        Puppeteer.launch(**options) do |browser|
          # Open a page to make sure its functional.
          browser.new_page
          expect(Dir[File.join(user_data_dir, "*")].count).to be > 0
        end
        expect(Dir[File.join(user_data_dir, "*")].count).to be > 0
      end
    end

    context 'with empty page' do
      sinatra do
        get('/empty.html') { "" }
      end

      it 'user_data_dir option should restore state' do
        Dir.mktmpdir do |user_data_dir|
          options = default_launch_options.merge(
            user_data_dir: user_data_dir,
          )

          Puppeteer.launch(**options) do |browser|
            # Open a page to make sure its functional.
            page = browser.new_page
            page.goto('http://localhost:4567/empty.html')
            page.evaluate("() => (localStorage.hey = 'hello')")
          end

          Puppeteer.launch(**options) do |browser|
            # Open a page to make sure its functional.
            page = browser.new_page
            page.goto('http://localhost:4567/empty.html')
            expect(page.evaluate("() => localStorage.hey")).to eq('hello')
          end
        end
      end

      it 'user_data_dir option should restore cookies' do
        Dir.mktmpdir do |user_data_dir|
          options = default_launch_options.merge(
            user_data_dir: user_data_dir,
          )

          Puppeteer.launch(**options) do |browser|
            # Open a page to make sure its functional.
            page = browser.new_page
            page.goto('http://localhost:4567/empty.html')
            js = <<~JAVASCRIPT
            () =>
              (document.cookie =
                'doSomethingOnlyOnce=true; expires=Fri, 31 Dec 9999 23:59:59 GMT')
            JAVASCRIPT
            page.evaluate(js)
          end

          Puppeteer.launch(**options) do |browser|
            # Open a page to make sure its functional.
            page = browser.new_page
            page.goto('http://localhost:4567/empty.html')
            expect(page.evaluate("() => document.cookie")).to eq('doSomethingOnlyOnce=true')
          end
        end
      end
    end

    it 'should return the default arguments' do
      if Puppeteer.env.firefox?
        expect(Puppeteer.default_args).to include(
          '--headless',
          '--no-remote',
          '--foreground',
        )
        expect(Puppeteer.default_args(headless: false)).not_to include('--headless')
        expect(Puppeteer.default_args(user_data_dir: 'foo')).to include(
          '--profile',
          'foo',
        )
      else
        expect(Puppeteer.default_args).to include(
          '--no-first-run',
          '--headless',
        )
        expect(Puppeteer.default_args(headless: false)).not_to include('--headless')
        expect(Puppeteer.default_args(user_data_dir: 'foo')).to include(
          '--user-data-dir=foo',
        )
      end
    end
#     it('should report the correct product', async () => {
#       const { isChrome, isFirefox, puppeteer } = getTestState();
#       if (isChrome) expect(puppeteer.product).toBe('chrome');
#       else if (isFirefox) expect(puppeteer.product).toBe('firefox');
#     });
#     it('should work with no default arguments', async () => {
#       const { defaultBrowserOptions, puppeteer } = getTestState();
#       const options = Object.assign({}, defaultBrowserOptions);
#       options.ignoreDefaultArgs = true;
#       const browser = await puppeteer.launch(options);
#       const page = await browser.newPage();
#       expect(await page.evaluate('11 * 11')).toBe(121);
#       await page.close();
#       await browser.close();
#     });
#     it('should filter out ignored default arguments', async () => {
#       const { defaultBrowserOptions, puppeteer } = getTestState();
#       // Make sure we launch with `--enable-automation` by default.
#       const defaultArgs = puppeteer.defaultArgs();
#       const browser = await puppeteer.launch(
#         Object.assign({}, defaultBrowserOptions, {
#           // Ignore first and third default argument.
#           ignoreDefaultArgs: [defaultArgs[0], defaultArgs[2]],
#         })
#       );
#       const spawnargs = browser.process().spawnargs;
#       if (!spawnargs) {
#         throw new Error('spawnargs not present');
#       }
#       expect(spawnargs.indexOf(defaultArgs[0])).toBe(-1);
#       expect(spawnargs.indexOf(defaultArgs[1])).not.toBe(-1);
#       expect(spawnargs.indexOf(defaultArgs[2])).toBe(-1);
#       await browser.close();
#     });
#     it('should have default URL when launching browser', async function () {
#       const { defaultBrowserOptions, puppeteer } = getTestState();
#       const browser = await puppeteer.launch(defaultBrowserOptions);
#       const pages = (await browser.pages()).map((page) => page.url());
#       expect(pages).toEqual(['about:blank']);
#       await browser.close();
#     });
#     itFailsFirefox(
#       'should have custom URL when launching browser',
#       async () => {
#         const { server, puppeteer, defaultBrowserOptions } = getTestState();

#         const options = Object.assign({}, defaultBrowserOptions);
#         options.args = [server.EMPTY_PAGE].concat(options.args || []);
#         const browser = await puppeteer.launch(options);
#         const pages = await browser.pages();
#         expect(pages.length).toBe(1);
#         const page = pages[0];
#         if (page.url() !== server.EMPTY_PAGE) await page.waitForNavigation();
#         expect(page.url()).toBe(server.EMPTY_PAGE);
#         await browser.close();
#       }
#     );
#     it('should set the default viewport', async () => {
#       const { puppeteer, defaultBrowserOptions } = getTestState();
#       const options = Object.assign({}, defaultBrowserOptions, {
#         defaultViewport: {
#           width: 456,
#           height: 789,
#         },
#       });
#       const browser = await puppeteer.launch(options);
#       const page = await browser.newPage();
#       expect(await page.evaluate('window.innerWidth')).toBe(456);
#       expect(await page.evaluate('window.innerHeight')).toBe(789);
#       await browser.close();
#     });
#     it('should disable the default viewport', async () => {
#       const { puppeteer, defaultBrowserOptions } = getTestState();
#       const options = Object.assign({}, defaultBrowserOptions, {
#         defaultViewport: null,
#       });
#       const browser = await puppeteer.launch(options);
#       const page = await browser.newPage();
#       expect(page.viewport()).toBe(null);
#       await browser.close();
#     });
#     it('should take fullPage screenshots when defaultViewport is null', async () => {
#       const { server, puppeteer, defaultBrowserOptions } = getTestState();

#       const options = Object.assign({}, defaultBrowserOptions, {
#         defaultViewport: null,
#       });
#       const browser = await puppeteer.launch(options);
#       const page = await browser.newPage();
#       await page.goto(server.PREFIX + '/grid.html');
#       const screenshot = await page.screenshot({
#         fullPage: true,
#       });
#       expect(screenshot).toBeInstanceOf(Buffer);
#       await browser.close();
#     });
#   });

#   describe('Puppeteer.launch', function () {
#     let productName;

#     before(async () => {
#       const { puppeteer } = getTestState();
#       productName = puppeteer._productName;
#     });

#     after(async () => {
#       const { puppeteer } = getTestState();
#       // @ts-expect-error launcher is a private property that users can't
#       // touch, but for testing purposes we need to reset it.
#       puppeteer._lazyLauncher = undefined;
#       puppeteer._productName = productName;
#     });

#     itOnlyRegularInstall('should be able to launch Chrome', async () => {
#       const { puppeteer } = getTestState();
#       const browser = await puppeteer.launch({ product: 'chrome' });
#       const userAgent = await browser.userAgent();
#       await browser.close();
#       expect(userAgent).toContain('Chrome');
#     });

#     it('falls back to launching chrome if there is an unknown product but logs a warning', async () => {
#       const { puppeteer } = getTestState();
#       const consoleStub = sinon.stub(console, 'warn');
#       // @ts-expect-error purposeful bad input
#       const browser = await puppeteer.launch({ product: 'SO_NOT_A_PRODUCT' });
#       const userAgent = await browser.userAgent();
#       await browser.close();
#       expect(userAgent).toContain('Chrome');
#       expect(consoleStub.callCount).toEqual(1);
#       expect(consoleStub.firstCall.args).toEqual([
#         'Warning: unknown product name SO_NOT_A_PRODUCT. Falling back to chrome.',
#       ]);
#     });

#     /* We think there's a bug in the FF Windows launcher, or some
#      * combo of that plus it running on CI, but it's hard to track down.
#      * See comment here: https://github.com/puppeteer/puppeteer/issues/5673#issuecomment-670141377.
#      */
#     itFailsWindows('should be able to launch Firefox', async function () {
#       this.timeout(FIREFOX_TIMEOUT);
#       const { puppeteer } = getTestState();
#       const browser = await puppeteer.launch({ product: 'firefox' });
#       const userAgent = await browser.userAgent();
#       await browser.close();
#       expect(userAgent).toContain('Firefox');
#     });
#   });

#   describe('Puppeteer.connect', function () {
#     it('should be able to connect multiple times to the same browser', async () => {
#       const { puppeteer, defaultBrowserOptions } = getTestState();

#       const originalBrowser = await puppeteer.launch(defaultBrowserOptions);
#       const otherBrowser = await puppeteer.connect({
#         browserWSEndpoint: originalBrowser.wsEndpoint(),
#       });
#       const page = await otherBrowser.newPage();
#       expect(await page.evaluate(() => 7 * 8)).toBe(56);
#       otherBrowser.disconnect();

#       const secondPage = await originalBrowser.newPage();
#       expect(await secondPage.evaluate(() => 7 * 6)).toBe(42);
#       await originalBrowser.close();
#     });
#     it('should be able to close remote browser', async () => {
#       const { defaultBrowserOptions, puppeteer } = getTestState();

#       const originalBrowser = await puppeteer.launch(defaultBrowserOptions);
#       const remoteBrowser = await puppeteer.connect({
#         browserWSEndpoint: originalBrowser.wsEndpoint(),
#       });
#       await Promise.all([
#         utils.waitEvent(originalBrowser, 'disconnected'),
#         remoteBrowser.close(),
#       ]);
#     });
#     it('should support ignoreHTTPSErrors option', async () => {
#       const {
#         httpsServer,
#         puppeteer,
#         defaultBrowserOptions,
#       } = getTestState();

#       const originalBrowser = await puppeteer.launch(defaultBrowserOptions);
#       const browserWSEndpoint = originalBrowser.wsEndpoint();

#       const browser = await puppeteer.connect({
#         browserWSEndpoint,
#         ignoreHTTPSErrors: true,
#       });
#       const page = await browser.newPage();
#       let error = null;
#       const [serverRequest, response] = await Promise.all([
#         httpsServer.waitForRequest('/empty.html'),
#         page.goto(httpsServer.EMPTY_PAGE).catch((error_) => (error = error_)),
#       ]);
#       expect(error).toBe(null);
#       expect(response.ok()).toBe(true);
#       expect(response.securityDetails()).toBeTruthy();
#       const protocol = serverRequest.socket.getProtocol().replace('v', ' ');
#       expect(response.securityDetails().protocol()).toBe(protocol);
#       await page.close();
#       await browser.close();
#     });
#     itFailsFirefox(
#       'should be able to reconnect to a disconnected browser',
#       async () => {
#         const { server, puppeteer, defaultBrowserOptions } = getTestState();

#         const originalBrowser = await puppeteer.launch(defaultBrowserOptions);
#         const browserWSEndpoint = originalBrowser.wsEndpoint();
#         const page = await originalBrowser.newPage();
#         await page.goto(server.PREFIX + '/frames/nested-frames.html');
#         originalBrowser.disconnect();

#         const browser = await puppeteer.connect({ browserWSEndpoint });
#         const pages = await browser.pages();
#         const restoredPage = pages.find(
#           (page) =>
#             page.url() === server.PREFIX + '/frames/nested-frames.html'
#         );
#         expect(utils.dumpFrames(restoredPage.mainFrame())).toEqual([
#           'http://localhost:<PORT>/frames/nested-frames.html',
#           '    http://localhost:<PORT>/frames/two-frames.html (2frames)',
#           '        http://localhost:<PORT>/frames/frame.html (uno)',
#           '        http://localhost:<PORT>/frames/frame.html (dos)',
#           '    http://localhost:<PORT>/frames/frame.html (aframe)',
#         ]);
#         expect(await restoredPage.evaluate(() => 7 * 8)).toBe(56);
#         await browser.close();
#       }
#     );
#     // @see https://github.com/puppeteer/puppeteer/issues/4197#issuecomment-481793410
#     itFailsFirefox(
#       'should be able to connect to the same page simultaneously',
#       async () => {
#         const { puppeteer } = getTestState();

#         const browserOne = await puppeteer.launch();
#         const browserTwo = await puppeteer.connect({
#           browserWSEndpoint: browserOne.wsEndpoint(),
#         });
#         const [page1, page2] = await Promise.all([
#           new Promise<Page>((x) =>
#             browserOne.once('targetcreated', (target) => x(target.page()))
#           ),
#           browserTwo.newPage(),
#         ]);
#         expect(await page1.evaluate(() => 7 * 8)).toBe(56);
#         expect(await page2.evaluate(() => 7 * 6)).toBe(42);
#         await browserOne.close();
#       }
#     );
#   });
#   describe('Puppeteer.executablePath', function () {
#     itOnlyRegularInstall('should work', async () => {
#       const { puppeteer } = getTestState();

#       const executablePath = puppeteer.executablePath();
#       expect(fs.existsSync(executablePath)).toBe(true);
#       expect(fs.realpathSync(executablePath)).toBe(executablePath);
#     });
#   });
# });

# describe('Browser target events', function () {
#   itFailsFirefox('should work', async () => {
#     const { server, puppeteer, defaultBrowserOptions } = getTestState();

#     const browser = await puppeteer.launch(defaultBrowserOptions);
#     const events = [];
#     browser.on('targetcreated', () => events.push('CREATED'));
#     browser.on('targetchanged', () => events.push('CHANGED'));
#     browser.on('targetdestroyed', () => events.push('DESTROYED'));
#     const page = await browser.newPage();
#     await page.goto(server.EMPTY_PAGE);
#     await page.close();
#     expect(events).toEqual(['CREATED', 'CHANGED', 'DESTROYED']);
#     await browser.close();
#   });
# });

# describe('Browser.Events.disconnected', function () {
#   it('should be emitted when: browser gets closed, disconnected or underlying websocket gets closed', async () => {
#     const { puppeteer, defaultBrowserOptions } = getTestState();
#     const originalBrowser = await puppeteer.launch(defaultBrowserOptions);
#     const browserWSEndpoint = originalBrowser.wsEndpoint();
#     const remoteBrowser1 = await puppeteer.connect({ browserWSEndpoint });
#     const remoteBrowser2 = await puppeteer.connect({ browserWSEndpoint });

#     let disconnectedOriginal = 0;
#     let disconnectedRemote1 = 0;
#     let disconnectedRemote2 = 0;
#     originalBrowser.on('disconnected', () => ++disconnectedOriginal);
#     remoteBrowser1.on('disconnected', () => ++disconnectedRemote1);
#     remoteBrowser2.on('disconnected', () => ++disconnectedRemote2);

#     await Promise.all([
#       utils.waitEvent(remoteBrowser2, 'disconnected'),
#       remoteBrowser2.disconnect(),
#     ]);

#     expect(disconnectedOriginal).toBe(0);
#     expect(disconnectedRemote1).toBe(0);
#     expect(disconnectedRemote2).toBe(1);

#     await Promise.all([
#       utils.waitEvent(remoteBrowser1, 'disconnected'),
#       utils.waitEvent(originalBrowser, 'disconnected'),
#       originalBrowser.close(),
#     ]);

#     expect(disconnectedOriginal).toBe(1);
#     expect(disconnectedRemote1).toBe(1);
#     expect(disconnectedRemote2).toBe(1);
#   });
# });
  end
end
