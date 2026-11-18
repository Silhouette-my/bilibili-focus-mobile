#if canImport(UIKit)
import Foundation

enum FocusWebAppearance {
    static func script(isDarkMode: Bool) -> String {
        let darkLiteral = isDarkMode ? "true" : "false"
        return """
        (function() {
          var isDark = \(darkLiteral);
          var background = isDark ? '#0F1115' : '#F6F7FA';
          var foreground = isDark ? '#F5F7FA' : '#111827';
          var root = document.documentElement;
          if (!root) {
            return;
          }
          var body = document.body;

          // 设置类名和属性
          root.classList.toggle('night-mode', isDark);
          root.classList.toggle('dark', isDark);
          root.classList.toggle('dark-mode', isDark);
          root.classList.toggle('light-mode', !isDark);
          root.setAttribute('data-theme', isDark ? 'dark' : 'light');
          root.setAttribute('data-focus-theme', isDark ? 'dark' : 'light');
          root.setAttribute('data-focus-platform', 'ios');
          root.style.colorScheme = isDark ? 'dark' : 'light';
          root.style.backgroundColor = background;
          root.style.color = foreground;
          root.style.setProperty('--focus-theme-background', background);
          root.style.setProperty('--focus-theme-foreground', foreground);

          if (body) {
            body.classList.toggle('night-mode', isDark);
            body.classList.toggle('dark', isDark);
            body.classList.toggle('dark-mode', isDark);
            body.classList.toggle('light-mode', !isDark);
            body.setAttribute('data-theme', isDark ? 'dark' : 'light');
            body.setAttribute('data-focus-theme', isDark ? 'dark' : 'light');
            body.style.colorScheme = isDark ? 'dark' : 'light';
            body.style.backgroundColor = background;
            body.style.color = foreground;
          }

          // 添加 meta 标签
          var head = document.head || root;
          var meta = document.querySelector('meta[name="color-scheme"]');
          if (!meta) {
            meta = document.createElement('meta');
            meta.name = 'color-scheme';
            head.appendChild(meta);
          }
          meta.content = isDark ? 'dark light' : 'light dark';

          var themeMeta = document.querySelector('meta[name="theme-color"]');
          if (!themeMeta) {
            themeMeta = document.createElement('meta');
            themeMeta.name = 'theme-color';
            head.appendChild(themeMeta);
          }
          themeMeta.content = background;
        })();
        """
    }

    static func bootstrapCSS(isDarkMode: Bool) -> String {
        let background = isDarkMode ? "#0F1115" : "#F6F7FA"
        let foreground = isDarkMode ? "#F5F7FA" : "#111827"
        return """
        (function() {
          var root = document.documentElement;
          if (!root) {
            return;
          }
          root.classList.remove('focus-bootstrap-theme-ready');
          root.classList.add('focus-bootstrap-theme-pending');
          var css = `
            :root {
              --focus-theme-background: \(background);
              --focus-theme-foreground: \(foreground);
            }

            html, body {
              background: var(--focus-theme-background) !important;
              color: var(--focus-theme-foreground) !important;
              color-scheme: \(isDarkMode ? "dark" : "light") !important;
            }

            html,
            body,
            #app,
            main,
            #mirror-vdcon,
            .video-container,
            .video-container-v1,
            .left-container,
            .right-container,
            .right-container-inner {
              background: var(--focus-theme-background) !important;
              color: var(--focus-theme-foreground) !important;
            }

            html::before {
              content: '';
              position: fixed;
              inset: 0;
              background: var(--focus-theme-background);
              z-index: 999999;
              pointer-events: none;
              opacity: 1;
              visibility: visible;
              transition: opacity 0.22s ease, visibility 0.22s ease;
            }

            html.focus-bootstrap-theme-ready::before {
              opacity: 0;
              visibility: hidden;
            }
          `;
          var style = document.getElementById('focus-bootstrap-theme');
          if (!style) {
            style = document.createElement('style');
            style.id = 'focus-bootstrap-theme';
            var head = document.head || document.documentElement;
            head.insertBefore(style, head.firstChild);
          }
          style.textContent = css;

          var finish = function() {
            root.classList.add('focus-bootstrap-theme-ready');
            root.classList.remove('focus-bootstrap-theme-pending');
          };
          requestAnimationFrame(function() {
            requestAnimationFrame(finish);
          });
          window.addEventListener('load', finish, { once: true });
          setTimeout(finish, 900);
        })();
        """
    }
}
#endif
