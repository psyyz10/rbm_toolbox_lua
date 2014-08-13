require('nn')
require('pl')
require('torch')


--- Sigmoid function
-- @x Tensor size [1,n_visible]
-- @return Tensor size [1,n_vislbe]
function sigm(x)
     local o = torch.exp(-x):add(1):pow(-1)
	return(o)
end

function printRBM(rbm,xt,xv,xs)
     print("---------------------RBM------------------------------------")
     
     if xt then print(string.format("Number of trainig samples    :  %i",xt:size(1))) end
     if xv then print(string.format("Number of validation samples :  %i",xv:size(1))) end
     if xs then print(string.format("Number of semi-sup samples   :  %i",xs:size(1))) end
     
     local ttype
     if rbm.alpha == 1 then ttype = "GENERATIVE"
     elseif rbm.alpha == 0 then ttype = "DISCRIMINATIVE"
     elseif rbm.alpha > 0 and rbm.alpha < 1 then ttype = "HYBRID"
     else assert(false, "alpha must be numeric between 0 and 1") end
     
     if rbm.beta > 0 then ttype = ttype .. " + SEMISUP" end
     
     print(string.format("Training type                :  %s",ttype))
     print(string.format("Number of visible            :  %i",rbm.W:size(2)))
     print(string.format("Number of hidden             :  %i",rbm.W:size(1)))
     print(string.format("Number of classes            :  %i",rbm.U:size(2)))
     print("")
     print(string.format("Number of epocs              :  %i",rbm.numepochs))
     print(string.format("Learning rate                :  %f",rbm.learningrate))
     print(string.format("Momentum                     :  %f",rbm.momentum))
     print(string.format("alpha                        :  %i",rbm.alpha))
     print(string.format("beta                         :  %i",rbm.beta))
     print(string.format("Temp file                    :  %s",rbm.tempfile))
     print("")
     
     
     print("REGULARIZATON")
     print(string.format("Patience                     :  %i",rbm.patience))
     print(string.format("Sparisty                     :  %f",rbm.sparsity))
     print(string.format("L1                           :  %f",rbm.L1))
     print(string.format("L2                           :  %f",rbm.L2))
     print(string.format("DropOut                      :  %f",rbm.dropout))
     print(string.format("DropConnect                  :  %f",rbm.dropconnect))
     print("------------------------------------------------------------")
    
end


--- Calculate p(y|x)
-- @rbm table 
-- @see rbmsetup
function pygivenx(rbm,x,tcwx_pre_calc)
     
     local tcwx,F,pyx
     tcwx_pre_calc = tcwx_pre_calc or torch.mm( x,rbm.W:t() ):add( rbm.c:t() )
     --F   = torch.add(rbm.U, tcwx_pre_calc:repeatTensor(rbm.U:size(2),1):t() );
     F   = torch.add( rbm.U,   torch.mm(tcwx_pre_calc:t(), rbm.one_by_classes)    )
     pyx = softplus(F):sum(1)                    -- p(y|x) logprob
     pyx:add(-torch.max(pyx))   -- divide by max,  log domain
     pyx:exp()   -- p(y|x) unnormalized prob     -- convert to real domain
     pyx:mul( ( 1/pyx:sum() ))  -- normalize probabilities
     
     
     -- OLD CODE
     --local p_y_given_x_log_prob = softplus(F):sum(1)   --log  prob
     --local p_y_given_x_not_norm = torch.add(p_y_given_x_log_prob, -torch.max(p_y_given_x_log_prob) ):exp()
     --local p_y_given_x = torch.mul(p_y_given_x_not_norm, (1/p_y_given_x_not_norm:sum()))
     
              

     
     return pyx,F
     
      
end


function softplus(x)  
     local o = torch.exp(x):add(1):log()
     --local o = nn.SoftPlus():forward(x)
     return(o)
end

function rbmup(rbm,x,y,randomGenerator) 
     local act_hid
     act_hid = torch.mm(x,rbm.W:t()):add(rbm.c:t())  -- x * rbm.W' + rbm.c'
     act_hid:add( torch.mm(y,rbm.U:t()) )
     act_hid = sigm(act_hid) 
     
     if randomGenerator then
          local act_hid_rnd = sampler(act_hid, randomGenerator)
          return act_hid, act_hid_rnd
     else
          return act_hid
     end
end

function rbmdownx(rbm,act_hid)
     local act_vis_x
     --act_vis_x =  -- hid_act * rbm.W + rbm.b'
     act_vis_x = sigm(torch.mm(act_hid,rbm.W):add(rbm.b:t()) );
     return act_vis_x
end

function rbmdowny(rbm,act_hid)
     local act_vis_y,normalizer
	act_vis_y = torch.mm( act_hid,rbm.U ):add( rbm.d:t() ):exp()
	normalizer = torch.sum(act_vis_y,2):expand(act_vis_y:size())
	act_vis_y:cdiv(normalizer)
	return act_vis_y
end

function samplevec(x,ran)
     local r,x_c,larger,sample
	r = ran(1,1):expand(x:size())
	x_c = torch.cumsum(x,2)
	larger = torch.ge(x_c,r)
	sample = torch.eq(torch.cumsum(larger,2),1):typeAs(x) 
	return sample
end

function sampler(dat,ran)
	local ret = torch.gt(dat, ran(1,dat:size(2))):typeAs(dat)
	return(ret)
end

function classprobs(rbm,x)
     local probs, n_visible,x_i,p_i
     n_visible = x:size(2)
     probs = torch.Tensor(x:size(1),rbm.n_classes)
     for i = 1, x:size(1) do
          x_i =x[i]:resize(1,n_visible)
          p_i = pygivenx(rbm,x_i)
          probs[{i,{}}] = p_i
     end
     return(probs)
end

function predict(rbm,x)
     local probs,_,pred
     probs = classprobs(rbm,x)
     _,pred=torch.max(probs,2)
     return pred:typeAs(x)  -- why does max return longtensor?
end

function accuracy(rbm,x,y_true)
     local pred,n_correct,acc,_
     --print(y_true)
     if y_true:size(2) ~= 1 then -- try max
          _,y_true = torch.max(y_true,2)
          y_true = y_true:typeAs(x)
     end
     
     pred = predict(rbm,x)
     n_correct = torch.eq(y_true,pred):sum()
     acc = n_correct / x:size(1)
     return(acc)
end

function initcrbm(m,n)
    -- initilize weigts from uniform distribution. As described in
    -- Learning Algorithms for the Classification Restricted Boltzmann
    -- machine
    local M = math.max(m,n);
    local interval_max = math.pow(M,-0.5);
    local interval_min = -interval_max;
    local weights = torch.rand(m,n):mul( interval_min + (interval_max-interval_min) )
    return weights
end


function rbmsetup(opts,x,y)
	local n_samples = x:size(1)
	local n_visible = x:size(2)
	local n_classes = y:size(2)

	local rbm = {}

	rbm.U = initcrbm(opts.n_hidden,n_classes)
	rbm.W = initcrbm(opts.n_hidden,n_visible)
	rbm.b = torch.zeros(n_visible,1)
	rbm.c = torch.zeros(opts.n_hidden,1)
	rbm.d = torch.zeros(n_classes,1)


	rbm.vW = torch.zeros(rbm.W:size()):zero()
	rbm.vU = torch.zeros(rbm.U:size()):zero()
	rbm.vb = torch.zeros(rbm.b:size()):zero()
	rbm.vc = torch.zeros(rbm.c:size()):zero()
	rbm.vd = torch.zeros(rbm.d:size()):zero()

     rbm.dW = torch.Tensor(rbm.W:size()):zero()
	rbm.dU = torch.Tensor(rbm.U:size()):zero()
	rbm.db = torch.Tensor(rbm.b:size()):zero()
	rbm.dc = torch.Tensor(rbm.c:size()):zero()
	rbm.dd = torch.Tensor(rbm.d:size()):zero()


	rbm.rand  = function(m,n) return torch.rand(m,n) end 
	rbm.n_classes = n_classes 
	rbm.n_visible = n_visible
	rbm.n_samples = n_samples
	rbm.numepochs = opts.numepochs or 5
	rbm.learningrate = opts.learningrate or 0.05
     rbm.alpha = opts.alpha or 1
     rbm.beta = opts.beta or 0
     rbm.momentum = opts.momentum or 0
     rbm.dropout = opts.dropout or 0
     rbm.dropconnect = opts.dropconnect or 0
     rbm.L1 = opts.L1 or 0
     rbm.L2 = opts.L2 or 0
     rbm.sparsity = opts.sparsity or 0
     rbm.err_recon_train    = torch.Tensor(rbm.numepochs):fill(-1)
     rbm.err_train    = torch.Tensor(rbm.numepochs):fill(-1)
     rbm.err_val    = torch.Tensor(rbm.numepochs):fill(-1)
     rbm.patience = opts.patience or 15
     rbm.tempfile = opts.tempfile or "temp_rbm.asc"
     
     
     -- prealocate som matrices
     rbm.one_by_classes  = torch.ones(1,rbm.U:size(2))
     rbm.hidden_by_one  = torch.ones(rbm.W:size(1),1)
     --rbm.pre_alloc_U  = torch.zeros(rbm.U:size())
	return(rbm)
end

function saverbm(filename,rbm)
     file = torch.DiskFile(filename, 'w')
     file:writeObject(rbm)
     file:close() -- make sure the data is written
end

function loadrbm(filename)
     file = torch.DiskFile(filename, 'r')
     rbm = file:readObject()
     return rbm
end


function checkequality(t1,t2,prec,pr)
	if pr then
		print(t1)
		print(t2)
	end 
	local prec = prec or -4
	assert(torch.numel(t1)==torch.numel(t1))
	
	local res = torch.add(t1,-t2):abs()
	res = torch.le(res, math.pow(10,prec))
	res = res:sum()
	local ret
	if torch.numel(t1) == res then
		ret = true
	else
		ret = false
	end

	return ret

end