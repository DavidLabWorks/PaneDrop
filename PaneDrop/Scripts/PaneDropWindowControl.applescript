on setWindowFrame(bundleIdentifier, windowTitle, currentX, currentY, targetX, targetY, targetWidth, targetHeight)
	tell application "System Events"
		set appProcess to first application process whose bundle identifier is bundleIdentifier
		set appWindows to every window of appProcess
		
		if (count of appWindows) is 0 then
			error "The target application has no windows."
		end if
		
		set targetWindow to first item of appWindows
		set closestDistance to 1.0E+20
		
		repeat with candidateWindow in appWindows
			try
				set candidatePosition to position of candidateWindow
				set deltaX to (item 1 of candidatePosition) - currentX
				set deltaY to (item 2 of candidatePosition) - currentY
				set candidateDistance to (deltaX * deltaX) + (deltaY * deltaY)
				
				if windowTitle is not "" then
					try
						if name of candidateWindow is windowTitle then
							set candidateDistance to candidateDistance - 1.0E+12
						end if
					end try
				end if
				
				if candidateDistance < closestDistance then
					set closestDistance to candidateDistance
					set targetWindow to candidateWindow
				end if
			end try
		end repeat
		
		-- Move first so macOS applies the destination screen's size constraints.
		-- Resizing on the source screen can clamp a full-screen target to that
		-- screen's shorter visible height.
		set position of targetWindow to {targetX, targetY}
		delay 0.1

		set didResize to false
		set resizeErrorMessage to ""
		set resizeErrorNumber to 0

		repeat 3 times
			try
				set size of targetWindow to {targetWidth, targetHeight}
				set didResize to true
				exit repeat
			on error errorMessage number errorNumber
				set resizeErrorMessage to errorMessage
				set resizeErrorNumber to errorNumber

				-- Moving across displays can switch Spaces and invalidate the
				-- original accessibility reference. Find the same window again
				-- at its destination before retrying the resize.
				set appWindows to every window of appProcess
				set closestDistance to 1.0E+20

				repeat with candidateWindow in appWindows
					try
						set candidatePosition to position of candidateWindow
						set deltaX to (item 1 of candidatePosition) - targetX
						set deltaY to (item 2 of candidatePosition) - targetY
						set candidateDistance to (deltaX * deltaX) + (deltaY * deltaY)

						if windowTitle is not "" then
							try
								if name of candidateWindow is windowTitle then
									set candidateDistance to candidateDistance - 1.0E+12
								end if
							end try
						end if

						if candidateDistance < closestDistance then
							set closestDistance to candidateDistance
							set targetWindow to candidateWindow
						end if
					end try
				end repeat

				delay 0.05
			end try
		end repeat
		
		if not didResize then
			error resizeErrorMessage number resizeErrorNumber
		end if

		return true
	end tell
end setWindowFrame
