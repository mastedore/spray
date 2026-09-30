-->> Sampling.spec.luau
--> The hash random and the sequence readers. Everything else is built on these being pure:
--> same inputs, same output, in any order.

return function()
	local Helpers = require(script.Parent.Helpers)
	local Sampling = require(Helpers.Package.Sampling)

	describe("Unit", function()
		it("returns the same number for the same seed, index and channel", function()
			for index = 0, 50 do
				expect(Sampling.Unit(Sampling.Stream(1234, index), 3)).to.equal(Sampling.Unit(Sampling.Stream(1234, index), 3))
			end
		end)

		it("stays inside [0, 1)", function()
			for index = 0, 2000 do
				local value = Sampling.Unit(Sampling.Stream(99, index), index % 15)
				expect(value >= 0 and value < 1).to.equal(true)
			end
		end)

		it("averages to about one half", function()
			local total = 0
			for index = 0, 3999 do
				total += Sampling.Unit(Sampling.Stream(7, index), 1)
			end
			expect(total / 4000).to.be.near(0.5, 0.03)
		end)

		it("gives unrelated values on different channels of the same particle", function()
			local matches = 0
			for index = 0, 199 do
				if Sampling.Unit(Sampling.Stream(5, index), 1) == Sampling.Unit(Sampling.Stream(5, index), 2) then
					matches += 1
				end
			end
			expect(matches).to.equal(0)
		end)

		it("changes with the seed", function()
			local differing = 0
			for index = 0, 99 do
				if Sampling.Unit(Sampling.Stream(1, index), 0) ~= Sampling.Unit(Sampling.Stream(2, index), 0) then
					differing += 1
				end
			end
			expect(differing).to.equal(100)
		end)

		-- Low bits lost to a naive 32-bit multiply show up as neighbouring indices that
		-- land close together. Adjacent draws should look nothing alike.
		it("does not clump neighbouring indices", function()
			local close = 0
			for index = 0, 999 do
				if math.abs(Sampling.Unit(Sampling.Stream(42, index), 0) - Sampling.Unit(Sampling.Stream(42, index + 1), 0)) < 0.001 then
					close += 1
				end
			end
			expect(close < 10).to.equal(true)
		end)
	end)

	describe("Signed", function()
		it("stays inside [-1, 1)", function()
			for index = 0, 500 do
				local value = Sampling.Signed(Sampling.Stream(3, index), 6)
				expect(value >= -1 and value < 1).to.equal(true)
			end
		end)
	end)

	describe("Range", function()
		it("returns Min when the range is a single value", function()
			expect(Sampling.Range(Sampling.Stream(1, 1), 1, NumberRange.new(4))).to.equal(4)
		end)

		it("stays between Min and Max", function()
			local range = NumberRange.new(-2, 5)
			for index = 0, 500 do
				local value = Sampling.Range(Sampling.Stream(8, index), 2, range)
				expect(value >= -2 and value <= 5).to.equal(true)
			end
		end)
	end)

	describe("Integer", function()
		it("hits every value in [Low, High] and nothing outside", function()
			local seen = {}
			for index = 0, 999 do
				local value = Sampling.Integer(Sampling.Stream(11, index), 12, 1, 4)
				expect(value >= 1 and value <= 4 and value == math.floor(value)).to.equal(true)
				seen[value] = true
			end
			for value = 1, 4 do
				expect(seen[value]).to.equal(true)
			end
		end)

		it("returns Low when the span is empty", function()
			expect(Sampling.Integer(Sampling.Stream(1, 1), 1, 3, 3)).to.equal(3)
			expect(Sampling.Integer(Sampling.Stream(1, 1), 1, 5, 2)).to.equal(5)
		end)
	end)

	describe("Number", function()
		local ramp = Sampling.NumberCurve(NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0, 0),
			NumberSequenceKeypoint.new(0.5, 10, 2),
			NumberSequenceKeypoint.new(1, 0, 0),
		}))

		it("reads keypoints exactly", function()
			expect(Sampling.Number(ramp, 0, 0)).to.equal(0)
			expect(Sampling.Number(ramp, 0.5, 0)).to.equal(10)
			expect(Sampling.Number(ramp, 1, 0)).to.equal(0)
		end)

		it("interpolates linearly between keypoints", function()
			expect(Sampling.Number(ramp, 0.25, 0)).to.be.near(5, 1e-6)
			expect(Sampling.Number(ramp, 0.75, 0)).to.be.near(5, 1e-6)
		end)

		it("adds the envelope scaled by the roll, interpolated too", function()
			expect(Sampling.Number(ramp, 0.5, 1)).to.be.near(12, 1e-6)
			expect(Sampling.Number(ramp, 0.5, -1)).to.be.near(8, 1e-6)
			expect(Sampling.Number(ramp, 0.25, 1)).to.be.near(6, 1e-6)
		end)

		it("holds the end values outside [0, 1]", function()
			local rising = Sampling.NumberCurve(NumberSequence.new(2, 6))
			expect(Sampling.Number(rising, -1, 0)).to.equal(2)
			expect(Sampling.Number(rising, 2, 0)).to.equal(6)
		end)
	end)

	describe("Color", function()
		local fade = Sampling.ColorCurve(ColorSequence.new(Color3.new(0, 0, 0), Color3.new(1, 1, 1)))

		it("interpolates in RGB", function()
			local middle = Sampling.Color(fade, 0.5)
			expect(middle.R).to.be.near(0.5, 1e-6)
			expect(middle.G).to.be.near(0.5, 1e-6)
			expect(middle.B).to.be.near(0.5, 1e-6)
		end)

		it("holds the end colours outside [0, 1]", function()
			expect(Sampling.Color(fade, -1)).to.equal(Color3.new(0, 0, 0))
			expect(Sampling.Color(fade, 2)).to.equal(Color3.new(1, 1, 1))
		end)
	end)

	describe("IsFlatColor", function()
		it("is true for one colour and false for a gradient", function()
			local flat = Sampling.ColorCurve(ColorSequence.new(Color3.new(1, 0, 0)))
			local gradient = Sampling.ColorCurve(ColorSequence.new(Color3.new(1, 0, 0), Color3.new(0, 0, 1)))
			expect(Sampling.IsFlatColor(flat)).to.equal(true)
			expect(Sampling.IsFlatColor(gradient)).to.equal(false)
		end)
	end)
end
