(setq org-export-with-broken-links false)
(setq org-publish-project-alist
      '(("harpwise-org"
	 :base-directory "~/git/harpwise/docs/_org"
	 :base-extension "org"
	 :publishing-directory "~/git/harpwise/docs/_html"
	 :recursive t
	 :publishing-function org-html-publish-to-html
	 :headline-levels 4
	 :html-extension "html"
	 :table-of-contents t
	 :body-only nil)

      ("harpwise-images"
	 :base-directory "~/git/harpwise/docs/images"
	 :base-extension "gif\\|png"
	 :publishing-directory "~/git/harpwise/docs/_html"
         :publishing-function org-publish-attachment)

    ("harpwise" :components ("harpwise-org" "harpwise-images"))))
