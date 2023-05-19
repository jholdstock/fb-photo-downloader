package main

import (
	"fmt"
	"regexp"

	"github.com/go-rod/rod"
	"github.com/go-rod/rod/lib/launcher"
	"github.com/go-rod/rod/lib/utils"
)

func main() {
	// Headless runs the browser on foreground, you can also use flag "-rod=show"
	// Devtools opens the tab in each new tab opened automatically
	l := launcher.NewUserMode().
		Headless(false).
		Devtools(false)

	defer l.Cleanup()

	debugURL := l.MustLaunch()

	browser := rod.New().
		ControlURL(debugURL).
		// Trace(true).
		// SlowMotion(1 * time.Second).
		MustConnect()

	defer browser.MustClose()

	urlPattern := "https://www.facebook.com/photo/?fbid=%s&set=%s"

	// Output config.
	id := 1
	dirs := []string{
		"album1",
		"album2",
	}

	// Crawler config.
	initUrl := []string{
		"https://www.facebook.com/photo/?fbid=pic&set=album",
		"https://www.facebook.com/photo/?fbid=pic&set=album",
	}

	urlRE := regexp.MustCompile(`fbid=(\d+)&set=(.+)`)

	for i, d := range dirs {
		res := urlRE.FindStringSubmatch(initUrl[i])

		firstImg := res[1]
		set := res[2]

		page := browser.MustPage(fmt.Sprintf(urlPattern, firstImg, set))
		regex := regexp.MustCompile(`\"nextMedia\":{\"edges\":\[{\"node\":{\"__typename\":\"Photo\",\"id\":\"(\d+)\",\"`)

		doingImg := firstImg

		for {
			wait := page.Browser().MustWaitDownload()

			page.MustElementX("//div[@aria-label='Actions for this post']").MustClick()
			page.MustElementX("//span[text()='Download']").MustClick()
			filename := fmt.Sprintf("%s/%04d.jpg", d, id)
			_ = utils.OutputFile(filename, wait())

			id++

			html, err := page.HTML()
			if err != nil {
				panic(err)
			}
			res := regex.FindStringSubmatch(html)

			nextImg := res[1]

			if nextImg == doingImg ||
				nextImg == firstImg {
				break
			}

			doingImg = nextImg

			page.Navigate(fmt.Sprintf(urlPattern, doingImg, set))

		}

		page.MustClose()
	}

}
