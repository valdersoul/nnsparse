require("nn")


dofile("SDAESparseCriterion.lua")
dofile("SDAECriterion.lua")
dofile("SparseTools.lua")

local sparsifier = function(x) if torch.uniform() < 0.6 then return 0 else return x end end

function torch.Tester:assertbw(val, condition, tolerance, message)
   self:assertgt(val, condition*(1-tolerance), message)
   self:assertlt(val, condition*(1+tolerance), message)
end


local function GetRatioOf(input, elem)
   local noHidden = 0
   local noElem   = 0
   for _, oneInput in pairs(input) do
      noHidden = noHidden + oneInput:eq(elem):sum()
      noElem   = noElem   + oneInput:size(1)
   end
   return noHidden/noElem
end


local tester = torch.Tester()



local SDAESparseCriterionTester = {}


function SDAESparseCriterionTester.prepareHidden()

   local input = torch.ones(10, 10000):apply(sparsifier):sparsify()
   
   local hideRatio = 0.5
   local criterion = nn.SDAESparseCriterion(nn.MSECriterion(), 
   {
      hideRatio = hideRatio
   })
   
   local noisyInput = criterion:prepareInput(input)
   local noHidden = GetRatioOf(noisyInput, 0)
   
   tester:assertbw(noHidden, hideRatio, 0.10, "Check number of corrupted input : Hidden")

end

function SDAESparseCriterionTester.prepareGauss()

   local input = torch.ones(10, 10000):apply(sparsifier):sparsify()
   
   local noiseRatio = 0.3
   local mean = 5
   local std = 2
   local criterion = nn.SDAESparseCriterion(nn.MSECriterion(), 
   {
      noiseRatio = noiseRatio,
      noiseMean  = mean,
      noiseStd   = std,
   })
   
   local noisyInput = criterion:prepareInput(input)
   
   for _, oneInput in pairs(noisyInput) do
   
      local oneInput = oneInput[{{}, 2}] --remove index

      local obtainedRatio = oneInput:ne(1):sum()/oneInput:size(1)
      
      local mask     = oneInput:ne(1)
      local obtainedMean  = oneInput[mask]:mean() - 1 
      local obtainedStd   = oneInput[mask]:std()
      
      tester:assertbw(obtainedRatio, noiseRatio, 0.10, "Check number of corrupted input : Gauss")
      tester:assertbw(obtainedMean,  mean      , 0.10, "Check number of corrupted input : Gauss (mean)")
      tester:assertbw(obtainedStd,   std       , 0.10, "Check number of corrupted input : Gauss (std)")
   end 
   
end


function SDAESparseCriterionTester.prepareSaltAndPepper()

   local input = torch.ones(10, 10000):apply(sparsifier):sparsify()
   
   local flipRatio = 0.8
   
   local criterion = nn.SDAESparseCriterion(nn.MSECriterion(), 
   {
      flipRatio = flipRatio,
      flipRange = {-99, 99},
   })
   
   local noisyInput = criterion:prepareInput(input)
   
   for _, oneInput in pairs(noisyInput) do
   
      local oneInput = oneInput[{{}, 2}] --remove index

      local noFlip = oneInput:eq( 99):sum()/oneInput:size(1)
      local noFlap = oneInput:eq(-99):sum()/oneInput:size(1)
      
      tester:assertbw(noFlip, flipRatio/2, 0.10, "Check number of corrupted input : SaltAndPepper")
      tester:assertbw(noFlap, flipRatio/2, 0.10, "Check number of corrupted input : SaltAndPepper")
   
   end 
   
end


function SDAESparseCriterionTester.prepareMixture()

   local input = torch.ones(10, 10000):apply(sparsifier):sparsify()
   
   local hideRatio  = 0.2
   local flipRatio  = 0.3
   
   local criterion = nn.SDAESparseCriterion(nn.MSECriterion(), 
   {
      hideRatio  = hideRatio,
      flipRatio  = flipRatio,
      flipRange  = {NaN, NaN},
   })
   
   local noisyInput = criterion:prepareInput(input)
   
   for _, oneInput in pairs(noisyInput) do
   
      local oneInput = oneInput[{{}, 2}] --remove index

      local noHide  = oneInput:eq( 0 ):sum()/oneInput:size(1)
      local noFlip  = oneInput:eq(NaN):sum()/oneInput:size(1)

      tester:assertbw(noHide , hideRatio , 0.10, "Check number of corrupted input : hide          (mixture)")
      tester:assertbw(noFlip , flipRatio , 0.10, "Check number of corrupted input : SaltAndPepper (mixture)")

   end 
   
end


function SDAESparseCriterionTester.NoNoise()


   local beta = 0.5
   
   local basicCriterion = nn.MSECriterion()
   local sdaeCriterion  = nn.SDAESparseCriterion(nn.MSECriterion(), 
   {
      alpha = 1,
      beta =  beta,
      hideRatio  = 0,
      noiseRatio = 0,
      flipRatio  = 0,
   })
   
   local input       = torch.ones(10, 100)
   local sparseInput = input:sparsify() 
   local noisyInput  = sdaeCriterion:prepareInput(sparseInput)

   local output = torch.Tensor(10, 100):uniform()
   
   
   local expectedLoss = basicCriterion:forward(output, input     )
   local obtainedLoss = sdaeCriterion:forward (output, noisyInput)

   tester:assertalmosteq(obtainedLoss, expectedLoss*beta, 1e-12, 'Fail to compute sparse SDAE loss with no noise')

   local expectedDLoss = basicCriterion:backward(output, input     )
   local obtainedDLoss = sdaeCriterion:backward (output, noisyInput)
   
   tester:assertTensorEq(obtainedDLoss, expectedDLoss:mul(beta), 1e-12, 'Fail to compute sparse SDAE Dloss with no noise')

end




function SDAESparseCriterionTester.WithNoise()

   local input       = torch.Tensor(10, 100):uniform():apply(sparsifier)
   
   
   local sparseInput = input:sparsify()
   local sparseMask  = input:ne(0)
   local output      = torch.Tensor(10, 100):uniform()
   
   local alpha = 0.8
   local beta  = 0.3
   
  local criterion = nn.SDAESparseCriterion(nn.MSECriterion(), 
  {
      hideRatio = 0.3,
      alpha = alpha,
      beta =  beta,
  })
  
  local noisyInput = criterion:prepareInput(sparseInput)
  
  -- retrieve the noise mask
  local maskAlpha
  local contiguousInput
  for k, mask in pairs(criterion.masks) do
      
      if maskAlpha  then maskAlpha = maskAlpha:cat(mask.alpha)
      else               maskAlpha = mask.alpha:clone()
      end 
      
      if contiguousInput then contiguousInput = contiguousInput:cat(noisyInput[k][{{},2}])
      else                    contiguousInput = noisyInput[k][{{},2}]
      end 
  end
  local maskBeta= maskAlpha:eq(0)
  


  -- compute the SDAE loss using the formula
  local diff = output[sparseMask]:clone():add(-1,contiguousInput):pow(2):view(-1)
  diff[maskAlpha] = diff[maskAlpha]* alpha
  diff[maskBeta ] = diff[maskBeta ]* beta

  local expectedLoss = diff:sum() / contiguousInput:nElement()
  local obtainedLoss = criterion:forward(output, noisyInput)
   
  tester:assertalmosteq(expectedLoss, obtainedLoss, 1e-6, 'Fail to compute SDAE Dloss with noise')



  -- compute the SDAE dloss using the formula
  local diff = output[sparseMask]:clone():add(-1,contiguousInput):mul(2):view(-1)
  diff[maskAlpha] = diff[maskAlpha]* alpha
  diff[maskBeta ] = diff[maskBeta ]* beta

  local expectedDLossSum = diff:sum() / input:nElement() -- WARNING input!
  local obtainedDLossSum = criterion:backward(output,noisyInput):sum()
  
  tester:assertalmosteq(expectedDLossSum, obtainedDLossSum, 1e-6, 'Fail to compute SDAE Dloss with noise')
  
end




print('')
print('Testing SDAECriterion.lua')
print('')

math.randomseed(os.time())


tester:add(SDAESparseCriterionTester)
tester:run()